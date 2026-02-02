// MARK: - ParseTreeVisualizer Tests

@testable import SwiftIndexCore
import Testing

@Suite("ParseTreeVisualizer Tests")
struct ParseTreeVisualizerTests {
    let visualizer = ParseTreeVisualizer()

    // MARK: - Basic Parsing

    @Test("Empty content returns empty result")
    func emptyContent() {
        let result = visualizer.visualize(content: "", path: "test.swift", options: .default)
        #expect(result.nodes.isEmpty)
        #expect(result.totalNodes == 0)
        #expect(result.maxDepth == 0)
        #expect(result.language == "swift")
    }

    @Test("Parse simple struct")
    func parseSimpleStruct() {
        let content = """
        struct Person {
            let name: String
            var age: Int
        }
        """

        let result = visualizer.visualize(content: content, path: "test.swift", options: .default)

        #expect(result.totalNodes == 3)
        #expect(result.maxDepth == 1)
        #expect(result.nodes.count == 1)

        let structNode = result.nodes[0]
        #expect(structNode.kind == "struct")
        #expect(structNode.name == "Person")
        #expect(structNode.children.count == 2)
        #expect(structNode.children[0].kind == "constant")
        #expect(structNode.children[0].name == "name")
        #expect(structNode.children[1].kind == "variable")
        #expect(structNode.children[1].name == "age")
    }

    @Test("Parse class with methods")
    func parseClassWithMethods() {
        let content = """
        class Calculator {
            func add(_ a: Int, _ b: Int) -> Int {
                return a + b
            }

            func subtract(_ a: Int, _ b: Int) -> Int {
                return a - b
            }
        }
        """

        let result = visualizer.visualize(content: content, path: "test.swift", options: .default)

        #expect(result.nodes.count == 1)
        let classNode = result.nodes[0]
        #expect(classNode.kind == "class")
        #expect(classNode.name == "Calculator")
        #expect(classNode.children.count == 2)
        #expect(classNode.children[0].kind == "method")
        #expect(classNode.children[0].name == "add")
        #expect(classNode.children[1].kind == "method")
        #expect(classNode.children[1].name == "subtract")
    }

    @Test("Parse nested types")
    func parseNestedTypes() {
        let content = """
        struct Outer {
            struct Inner {
                let value: Int
            }
            let inner: Inner
        }
        """

        let result = visualizer.visualize(content: content, path: "test.swift", options: .default)

        #expect(result.maxDepth == 2)
        let outerNode = result.nodes[0]
        #expect(outerNode.kind == "struct")
        #expect(outerNode.name == "Outer")

        // Inner struct and outer's property
        let innerStruct = outerNode.children.first { $0.kind == "struct" }
        #expect(innerStruct?.name == "Inner")
        #expect(innerStruct?.depth == 1)
        #expect(innerStruct?.children.count == 1)
    }

    @Test("Parse extension")
    func parseExtension() {
        let content = """
        struct MyType {}

        extension MyType {
            func doSomething() {}
        }
        """

        let result = visualizer.visualize(content: content, path: "test.swift", options: .default)

        #expect(result.nodes.count == 2)
        let extensionNode = result.nodes[1]
        #expect(extensionNode.kind == "extension")
        #expect(extensionNode.name == "MyType")
        #expect(extensionNode.children.count == 1)
        #expect(extensionNode.children[0].kind == "method")
    }

    @Test("Parse protocol")
    func parseProtocol() {
        let content = """
        protocol Greetable {
            var name: String { get }
            func greet() -> String
        }
        """

        let result = visualizer.visualize(content: content, path: "test.swift", options: .default)

        #expect(result.nodes.count == 1)
        let protocolNode = result.nodes[0]
        #expect(protocolNode.kind == "protocol")
        #expect(protocolNode.name == "Greetable")
        #expect(protocolNode.children.count == 2)
    }

    @Test("Parse actor")
    func parseActor() {
        let content = """
        actor Counter {
            private var count = 0

            func increment() {
                count += 1
            }
        }
        """

        let result = visualizer.visualize(content: content, path: "test.swift", options: .default)

        #expect(result.nodes.count == 1)
        let actorNode = result.nodes[0]
        #expect(actorNode.kind == "actor")
        #expect(actorNode.name == "Counter")
    }

    @Test("Parse enum with cases")
    func parseEnum() {
        let content = """
        enum Direction {
            case north
            case south
            case east
            case west
        }
        """

        let result = visualizer.visualize(content: content, path: "test.swift", options: .default)

        #expect(result.nodes.count == 1)
        let enumNode = result.nodes[0]
        #expect(enumNode.kind == "enum")
        #expect(enumNode.name == "Direction")
    }

    // MARK: - Filtering

    @Test("Filter by kind - single type")
    func kindFilterSingle() {
        let content = """
        struct MyStruct {
            let value: Int
            func doWork() {}
        }

        class MyClass {
            func process() {}
        }
        """

        let options = ParseTreeOptions(kindFilter: ["struct"])
        let result = visualizer.visualize(content: content, path: "test.swift", options: options)

        #expect(result.nodes.count == 1)
        #expect(result.nodes[0].kind == "struct")
        #expect(result.nodes[0].name == "MyStruct")
        // Children should be empty because they are filtered out
        #expect(result.nodes[0].children.isEmpty)
    }

    @Test("Filter by kind - methods only")
    func kindFilterMethods() {
        let content = """
        struct Container {
            let value: Int
            func first() {}
            func second() {}
        }
        """

        let options = ParseTreeOptions(kindFilter: ["method"])
        let result = visualizer.visualize(content: content, path: "test.swift", options: options)

        // Methods should be promoted to root level since struct is filtered out
        #expect(result.nodes.count == 2)
        #expect(result.nodes.allSatisfy { $0.kind == "method" })
    }

    @Test("Filter by kind - multiple types")
    func kindFilterMultiple() {
        let content = """
        struct MyStruct {
            let value: Int
            func doWork() {}
        }

        class MyClass {
            var count: Int = 0
            func process() {}
        }
        """

        let options = ParseTreeOptions(kindFilter: ["struct", "class"])
        let result = visualizer.visualize(content: content, path: "test.swift", options: options)

        #expect(result.nodes.count == 2)
        #expect(result.nodes[0].kind == "struct")
        #expect(result.nodes[1].kind == "class")
    }

    // MARK: - Depth Limiting

    @Test("Max depth limiting")
    func maxDepthLimiting() {
        let content = """
        struct Outer {
            struct Middle {
                struct Inner {
                    let value: Int
                }
            }
        }
        """

        let options = ParseTreeOptions(maxDepth: 1)
        let result = visualizer.visualize(content: content, path: "test.swift", options: options)

        #expect(result.nodes.count == 1)
        let outerNode = result.nodes[0]
        #expect(outerNode.kind == "struct")
        // At depth 1, we should have Middle but its children should be cut off
        #expect(outerNode.children.isEmpty)
    }

    @Test("Max depth 2 includes one level of children")
    func maxDepthTwo() {
        let content = """
        struct Outer {
            struct Middle {
                struct Inner {
                    let value: Int
                }
            }
        }
        """

        let options = ParseTreeOptions(maxDepth: 2)
        let result = visualizer.visualize(content: content, path: "test.swift", options: options)

        let outerNode = result.nodes[0]
        #expect(!outerNode.children.isEmpty)
        let middleNode = outerNode.children[0]
        #expect(middleNode.kind == "struct")
        #expect(middleNode.name == "Middle")
        // Inner should be cut off
        #expect(middleNode.children.isEmpty)
    }

    // MARK: - Output Formats

    @Test("TOON format output")
    func tOONFormat() {
        let content = """
        struct Simple {
            let value: Int
        }
        """

        let result = visualizer.visualize(content: content, path: "test.swift", options: .default)
        let output = visualizer.formatTOON(result)

        #expect(output.contains("ast{path,lang,nodes,depth}:"))
        #expect(output.contains("\"swift\""))
        #expect(output.contains("tree["))
        #expect(output.contains("\"struct\""))
        #expect(output.contains("\"Simple\""))
    }

    @Test("Human format output")
    func humanFormat() {
        let content = """
        struct Simple {
            let value: Int
        }
        """

        let result = visualizer.visualize(content: content, path: "test.swift", options: .default)
        let output = visualizer.formatHuman(result)

        #expect(output.contains("test.swift"))
        #expect(output.contains("swift"))
        #expect(output.contains("2 nodes"))
        #expect(output.contains("struct Simple"))
        #expect(output.contains("└──") || output.contains("├──"))
    }

    @Test("JSON format output")
    func jSONFormat() throws {
        let content = """
        struct Simple {
            let value: Int
        }
        """

        let result = visualizer.visualize(content: content, path: "test.swift", options: .default)
        let output = try visualizer.formatJSON(result)

        #expect(output.contains("\"path\""))
        #expect(output.contains("\"language\""))
        #expect(output.contains("\"nodes\""))
        #expect(output.contains("\"totalNodes\""))
        #expect(output.contains("\"maxDepth\""))
    }

    // MARK: - Language Detection

    @Test("Detect Swift language")
    func detectSwiftLanguage() {
        let result = visualizer.visualize(content: "let x = 1", path: "test.swift", options: .default)
        #expect(result.language == "swift")
    }

    @Test("Detect Objective-C language")
    func detectObjectiveCLanguage() {
        let result = visualizer.visualize(content: "", path: "test.m", options: .default)
        #expect(result.language == "objective-c")
    }

    @Test("Detect C++ language")
    func detectCppLanguage() {
        let result = visualizer.visualize(content: "", path: "test.cpp", options: .default)
        #expect(result.language == "cpp")
    }

    // MARK: - Signatures

    @Test("Signature includes modifiers")
    func signatureWithModifiers() {
        let content = """
        public final class MyClass {
            private var count: Int = 0
            public func doWork() async throws {}
        }
        """

        let result = visualizer.visualize(content: content, path: "test.swift", options: .default)

        let classNode = result.nodes[0]
        #expect(classNode.signature?.contains("public") == true)
        #expect(classNode.signature?.contains("final") == true)
        #expect(classNode.signature?.contains("class") == true)

        let methodNode = classNode.children.first { $0.kind == "method" }
        #expect(methodNode?.signature?.contains("public") == true)
        #expect(methodNode?.signature?.contains("async") == true)
        #expect(methodNode?.signature?.contains("throws") == true)
    }

    @Test("Signature includes inheritance")
    func signatureWithInheritance() {
        let content = """
        struct MyStruct: Codable, Sendable {
            let value: Int
        }
        """

        let result = visualizer.visualize(content: content, path: "test.swift", options: .default)

        let structNode = result.nodes[0]
        #expect(structNode.signature?.contains("Codable") == true)
        #expect(structNode.signature?.contains("Sendable") == true)
    }

    // MARK: - Line Numbers

    @Test("Line numbers are accurate")
    func lineNumbers() {
        let content = """
        // Comment line 1
        // Comment line 2
        struct MyStruct {
            let value: Int
        }
        """

        let result = visualizer.visualize(content: content, path: "test.swift", options: .default)

        let structNode = result.nodes[0]
        #expect(structNode.startLine == 3)
        #expect(structNode.endLine == 5)
    }
}

// MARK: - Batch Result Tests

@Suite("ParseTreeVisualizer Batch Tests")
struct ParseTreeVisualizerBatchTests {
    let visualizer = ParseTreeVisualizer()

    @Test("Batch TOON format")
    func batchTOONFormat() {
        let file1 = ParseTreeResult(
            nodes: [ASTNode(kind: "struct", name: "A", startLine: 1, endLine: 5, depth: 0)],
            totalNodes: 1,
            maxDepth: 0,
            path: "A.swift",
            language: "swift"
        )
        let file2 = ParseTreeResult(
            nodes: [ASTNode(kind: "class", name: "B", startLine: 1, endLine: 10, depth: 0)],
            totalNodes: 1,
            maxDepth: 0,
            path: "B.swift",
            language: "swift"
        )

        let batch = ParseTreeBatchResult(
            files: [file1, file2],
            totalFiles: 2,
            totalNodes: 2,
            maxDepth: 0,
            rootPath: "Sources/"
        )

        let output = visualizer.formatTOON(batch)

        #expect(output.contains("batch{root,files,nodes,depth}:"))
        #expect(output.contains("\"Sources/\""))
        #expect(output.contains("file[0]"))
        #expect(output.contains("file[1]"))
        #expect(output.contains("A.swift"))
        #expect(output.contains("B.swift"))
    }

    @Test("Batch Human format")
    func batchHumanFormat() {
        let file1 = ParseTreeResult(
            nodes: [ASTNode(kind: "struct", name: "A", startLine: 1, endLine: 5, depth: 0)],
            totalNodes: 1,
            maxDepth: 0,
            path: "A.swift",
            language: "swift"
        )

        let batch = ParseTreeBatchResult(
            files: [file1],
            totalFiles: 1,
            totalNodes: 1,
            maxDepth: 0,
            rootPath: "Sources/"
        )

        let output = visualizer.formatHuman(batch)

        #expect(output.contains("Sources/"))
        #expect(output.contains("1 files"))
        #expect(output.contains("1 nodes"))
        #expect(output.contains("A.swift"))
    }
}
