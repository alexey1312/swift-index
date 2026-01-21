// MARK: - SwiftSyntaxParser Tests

@testable import SwiftIndexCore
import Testing

@Suite("SwiftSyntaxParser Tests")
struct SwiftSyntaxParserTests {
    let parser = SwiftSyntaxParser()

    // MARK: - Basic Parser Properties

    @Test("Parser supports .swift extension")
    func testSupportedExtensions() {
        #expect(parser.supportedExtensions == ["swift"])
    }

    @Test("Empty content returns failure")
    func testEmptyContent() {
        let result = parser.parse(content: "", path: "/test.swift")
        guard case let .failure(error) = result else {
            Issue.record("Expected failure for empty content")
            return
        }
        #expect(error == .emptyContent)
    }

    // MARK: - Function Parsing

    @Test("Parse free function")
    func parseFreeFunction() {
        let content = """
        /// Calculates the sum of two numbers.
        func add(_ a: Int, _ b: Int) -> Int {
            return a + b
        }
        """

        let result = parser.parse(content: content, path: "/test.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(chunks.count == 1)

        let chunk = chunks[0]
        #expect(chunk.kind == .function)
        #expect(chunk.symbols.contains("add"))
        #expect(chunk.startLine == 2)
        #expect(chunk.endLine == 4)
        #expect(chunk.content.contains("Calculates the sum"))
    }

    @Test("Parse async throwing function")
    func parseAsyncThrowingFunction() {
        let content = """
        func fetchData(from url: URL) async throws -> Data {
            try await URLSession.shared.data(from: url).0
        }
        """

        let result = parser.parse(content: content, path: "/test.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(chunks.count == 1)

        let chunk = chunks[0]
        #expect(chunk.kind == .function)
        #expect(chunk.symbols.contains("fetchData"))
    }

    // MARK: - Class Parsing

    @Test("Parse class with methods")
    func parseClassWithMethods() {
        let content = """
        /// A person with a name.
        class Person {
            let name: String

            init(name: String) {
                self.name = name
            }

            func greet() -> String {
                "Hello, \\(name)"
            }
        }
        """

        let result = parser.parse(content: content, path: "/test.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        // Should have: class, constant (name), initializer, method
        #expect(chunks.count >= 3)

        let classChunk = chunks.first { $0.kind == .class }
        #expect(classChunk != nil)
        #expect(classChunk?.symbols.contains("Person") == true)

        let initChunk = chunks.first { $0.kind == .initializer }
        #expect(initChunk != nil)
        #expect(initChunk?.symbols.contains("Person.init") == true)

        let methodChunk = chunks.first { $0.kind == .method }
        #expect(methodChunk != nil)
        #expect(methodChunk?.symbols.contains("Person.greet") == true)
    }

    // MARK: - Struct Parsing

    @Test("Parse struct with computed property")
    func parseStructWithComputedProperty() {
        let content = """
        struct Point {
            var x: Double
            var y: Double

            var magnitude: Double {
                (x * x + y * y).squareRoot()
            }
        }
        """

        let result = parser.parse(content: content, path: "/test.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        let structChunk = chunks.first { $0.kind == .struct }
        #expect(structChunk != nil)
        #expect(structChunk?.symbols.contains("Point") == true)

        // Variables should be captured
        let variables = chunks.filter { $0.kind == .variable }
        #expect(variables.count >= 2)
    }

    // MARK: - Enum Parsing

    @Test("Parse enum with associated values")
    func parseEnumWithAssociatedValues() {
        let content = """
        /// Result type for operations.
        enum Result<Success, Failure: Error> {
            case success(Success)
            case failure(Failure)
        }
        """

        let result = parser.parse(content: content, path: "/test.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        let enumChunk = chunks.first { $0.kind == .enum }
        #expect(enumChunk != nil)
        #expect(enumChunk?.symbols.contains("Result") == true)
        #expect(enumChunk?.content.contains("Result type for operations") == true)
    }

    // MARK: - Protocol Parsing

    @Test("Parse protocol with requirements")
    func parseProtocolWithRequirements() {
        let content = """
        /// A type that can be identified.
        protocol Identifiable {
            associatedtype ID: Hashable
            var id: ID { get }
        }
        """

        let result = parser.parse(content: content, path: "/test.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        let protocolChunk = chunks.first { $0.kind == .protocol }
        #expect(protocolChunk != nil)
        #expect(protocolChunk?.symbols.contains("Identifiable") == true)
    }

    // MARK: - Extension Parsing

    @Test("Parse extension with conformance")
    func parseExtensionWithConformance() {
        let content = """
        extension String: Identifiable {
            var id: String { self }
        }
        """

        let result = parser.parse(content: content, path: "/test.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        let extensionChunk = chunks.first { $0.kind == .extension }
        #expect(extensionChunk != nil)
        #expect(extensionChunk?.symbols.contains("String") == true)
    }

    // MARK: - Actor Parsing

    @Test("Parse actor")
    func parseActor() {
        let content = """
        /// A thread-safe counter.
        actor Counter {
            private var count = 0

            func increment() {
                count += 1
            }

            func value() -> Int {
                count
            }
        }
        """

        let result = parser.parse(content: content, path: "/test.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        let actorChunk = chunks.first { $0.kind == .actor }
        #expect(actorChunk != nil)
        #expect(actorChunk?.symbols.contains("Counter") == true)

        // Methods inside actor should be captured
        let methods = chunks.filter { $0.kind == .method }
        #expect(methods.count == 2)
    }

    // MARK: - Nested Types

    @Test("Parse nested types")
    func parseNestedTypes() {
        let content = """
        struct Outer {
            struct Inner {
                let value: Int
            }

            enum Status {
                case active
                case inactive
            }
        }
        """

        let result = parser.parse(content: content, path: "/test.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        // Should have outer struct, inner struct, and enum
        let structs = chunks.filter { $0.kind == .struct }
        #expect(structs.count == 2)

        let innerStruct = chunks.first { $0.symbols.contains("Outer.Inner") }
        #expect(innerStruct != nil)

        let nestedEnum = chunks.first { $0.symbols.contains("Outer.Status") }
        #expect(nestedEnum != nil)
    }

    // MARK: - Initializers

    @Test("Parse failable initializer")
    func parseFailableInitializer() {
        let content = """
        struct URL {
            init?(string: String) {
                guard !string.isEmpty else { return nil }
            }
        }
        """

        let result = parser.parse(content: content, path: "/test.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        let initChunk = chunks.first { $0.kind == .initializer }
        #expect(initChunk != nil)
    }

    // MARK: - Subscripts

    @Test("Parse subscript")
    func parseSubscript() {
        let content = """
        struct Matrix {
            subscript(row: Int, column: Int) -> Double {
                get { 0.0 }
                set { }
            }
        }
        """

        let result = parser.parse(content: content, path: "/test.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        let subscriptChunk = chunks.first { $0.kind == .subscript }
        #expect(subscriptChunk != nil)
        #expect(subscriptChunk?.symbols.contains("Matrix.subscript") == true)
    }

    // MARK: - Type Alias

    @Test("Parse typealias")
    func parseTypealias() {
        let content = """
        /// A completion handler type.
        typealias CompletionHandler = (Result<Data, Error>) -> Void
        """

        let result = parser.parse(content: content, path: "/test.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        let typealiasChunk = chunks.first { $0.kind == .typealias }
        #expect(typealiasChunk != nil)
        #expect(typealiasChunk?.symbols.contains("CompletionHandler") == true)
    }

    // MARK: - Doc Comments

    @Test("Extract doc block comments")
    func extractDocBlockComments() {
        let content = """
        /**
         * Processes the input data.
         *
         * - Parameter data: The data to process.
         * - Returns: Processed data.
         */
        func process(data: Data) -> Data {
            data
        }
        """

        let result = parser.parse(content: content, path: "/test.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        let chunk = chunks[0]
        #expect(chunk.content.contains("Processes the input data"))
    }

    // MARK: - References

    @Test("Extract type references")
    func extractTypeReferences() {
        let content = """
        func convert(person: Person) -> PersonDTO {
            PersonDTO(name: person.name)
        }
        """

        let result = parser.parse(content: content, path: "/test.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        let chunk = chunks[0]
        #expect(chunk.references.contains("Person"))
        #expect(chunk.references.contains("PersonDTO"))
    }

    // MARK: - File Hash

    @Test("Same content produces same hash")
    func fileHashConsistency() {
        let content = "func test() {}"

        let result1 = parser.parse(content: content, path: "/test1.swift")
        let result2 = parser.parse(content: content, path: "/test2.swift")

        guard case let .success(chunks1) = result1,
              case let .success(chunks2) = result2
        else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(chunks1[0].fileHash == chunks2[0].fileHash)
    }

    @Test("Different content produces different hash")
    func fileHashDifference() {
        let content1 = "func test1() {}"
        let content2 = "func test2() {}"

        let result1 = parser.parse(content: content1, path: "/test.swift")
        let result2 = parser.parse(content: content2, path: "/test.swift")

        guard case let .success(chunks1) = result1,
              case let .success(chunks2) = result2
        else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(chunks1[0].fileHash != chunks2[0].fileHash)
    }

    // MARK: - Chunk IDs

    @Test("Chunk IDs are deterministic")
    func chunkIdDeterminism() {
        let content = "func test() {}"

        let result1 = parser.parse(content: content, path: "/test.swift")
        let result2 = parser.parse(content: content, path: "/test.swift")

        guard case let .success(chunks1) = result1,
              case let .success(chunks2) = result2
        else {
            Issue.record("Expected successful parse")
            return
        }

        #expect(chunks1[0].id == chunks2[0].id)
    }

    // MARK: - Complex Fixture

    @Test("Parse complex fixture file")
    func parseComplexFixture() {
        let content = """
        import Foundation

        /// A sample protocol for testing.
        protocol Greetable {
            var name: String { get }
            func greet() -> String
        }

        /// A sample class for testing.
        class Person: Greetable {
            let name: String
            private var age: Int

            init(name: String, age: Int) {
                self.name = name
                self.age = age
            }

            func greet() -> String {
                "Hello, my name is \\(name)"
            }

            func birthday() {
                age += 1
            }
        }

        /// A sample struct for testing.
        struct Point {
            var x: Double
            var y: Double

            func distance(to other: Point) -> Double {
                let dx = x - other.x
                let dy = y - other.y
                return (dx * dx + dy * dy).squareRoot()
            }
        }

        /// A sample enum for testing.
        enum Direction: String, CaseIterable {
            case north, south, east, west

            var opposite: Direction {
                switch self {
                case .north: return .south
                case .south: return .north
                case .east: return .west
                case .west: return .east
                }
            }
        }

        /// A sample actor for testing.
        actor Counter {
            private var count = 0

            func increment() {
                count += 1
            }

            func value() -> Int {
                count
            }
        }

        /// Extension for testing.
        extension Person {
            var description: String {
                "\\(name), age \\(age)"
            }
        }

        /// A free function for testing.
        func calculateSum(_ numbers: [Int]) -> Int {
            numbers.reduce(0, +)
        }
        """

        let result = parser.parse(content: content, path: "/SampleSwift.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        // Verify we found all major declarations
        let protocols = chunks.filter { $0.kind == .protocol }
        let classes = chunks.filter { $0.kind == .class }
        let structs = chunks.filter { $0.kind == .struct }
        let enums = chunks.filter { $0.kind == .enum }
        let actors = chunks.filter { $0.kind == .actor }
        let extensions = chunks.filter { $0.kind == .extension }
        let functions = chunks.filter { $0.kind == .function }
        let methods = chunks.filter { $0.kind == .method }
        let initializers = chunks.filter { $0.kind == .initializer }

        #expect(protocols.count == 1, "Should have 1 protocol")
        #expect(classes.count == 1, "Should have 1 class")
        #expect(structs.count == 1, "Should have 1 struct")
        #expect(enums.count == 1, "Should have 1 enum")
        #expect(actors.count == 1, "Should have 1 actor")
        #expect(extensions.count == 1, "Should have 1 extension")
        #expect(functions.count == 1, "Should have 1 free function")
        #expect(methods.count >= 5, "Should have at least 5 methods")
        #expect(initializers.count == 1, "Should have 1 initializer")
    }

    // MARK: - Generic Types

    @Test("Parse generic struct with where clause")
    func parseGenericStructWithWhereClause() {
        let content = """
        struct Container<Element> where Element: Equatable {
            var items: [Element] = []

            mutating func add(_ item: Element) {
                items.append(item)
            }
        }
        """

        let result = parser.parse(content: content, path: "/test.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        let structChunk = chunks.first { $0.kind == .struct }
        #expect(structChunk != nil)
        #expect(structChunk?.symbols.contains("Container") == true)
    }

    // MARK: - Access Modifiers

    @Test("Parse declarations with access modifiers")
    func parseAccessModifiers() {
        let content = """
        public final class Service {
            private let cache: [String: Any]

            public init() {
                cache = [:]
            }

            internal func process() {}

            fileprivate func helper() {}
        }
        """

        let result = parser.parse(content: content, path: "/test.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Expected successful parse")
            return
        }

        let classChunk = chunks.first { $0.kind == .class }
        #expect(classChunk != nil)
        #expect(classChunk?.content.contains("public final class") == true)

        let methods = chunks.filter { $0.kind == .method }
        #expect(methods.count == 2)
    }
}
