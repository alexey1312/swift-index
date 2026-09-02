// MARK: - SwiftGraphFactsExtractor

import Foundation
import SwiftParser
import SwiftSyntax

/// Extracts symbols and references for the call graph.
///
/// Runs as a separate visitor from the chunker because the two want different things:
/// the chunker skips local variables and treats a type as one unit, while the graph
/// needs local bindings (to type call receivers) and a node per member.
public enum SwiftGraphFactsExtractor {
    /// Names that produce nothing but noise as edge targets.
    ///
    /// Without a stoplist the great majority of edges are stdlib member accesses on
    /// unknown receivers — `map`, `count`, `append` — which no one wants to traverse
    /// and which drown the useful structure.
    static let ignoredNames: Set<String> = [
        "self", "Self", "super", "init", "map", "filter", "reduce", "compactMap",
        "flatMap", "forEach", "count", "append", "first", "last", "isEmpty", "joined",
        "description", "rawValue", "hashValue", "sorted", "contains", "removeAll",
        "insert", "remove", "keys", "values", "min", "max", "prefix", "suffix",
        "String", "Int", "Bool", "Double", "Float", "Array", "Dictionary", "Set",
        "Optional", "Void", "Data", "URL", "Date", "Error", "Result", "Task",
        "print", "assert", "precondition", "fatalError",
        // Unambiguous stdlib String/Sequence members. Measured on this repo, these
        // alone accounted for a large share of permanently-unresolvable call edges.
        // Deliberately excludes names like `write`, `read` and `execute`, which are
        // plausible project methods and must not be silently dropped.
        "lowercased", "uppercased", "trimmingCharacters", "hasPrefix", "hasSuffix",
        "enumerated", "split", "joined", "replacingOccurrences", "components",
        "dropFirst", "dropLast", "reversed", "starts", "distance", "index",
        "allSatisfy", "reserveCapacity", "withUnsafeBytes",
    ]

    /// Parses Swift source into graph facts.
    ///
    /// - Parameters:
    ///   - content: Source text.
    ///   - path: File path.
    ///   - fileHash: Content hash of the file.
    ///   - module: Inferred module name.
    /// - Returns: Symbols, references and imports for the file.
    public static func extract(
        content: String,
        path: String,
        fileHash: String,
        module: String?
    ) -> FileGraphFacts {
        let sourceFile = SwiftParser.Parser.parse(source: content)
        let converter = SourceLocationConverter(fileName: path, tree: sourceFile)
        let visitor = GraphVisitor(
            path: path,
            fileHash: fileHash,
            module: module,
            converter: converter
        )
        visitor.walk(sourceFile)

        return FileGraphFacts(
            path: path,
            fileHash: fileHash,
            symbols: visitor.symbols,
            references: visitor.references,
            imports: visitor.imports,
            localTypes: visitor.localTypes
        )
    }
}

// MARK: - GraphVisitor

/// Collects declarations and the references inside them.
final class GraphVisitor: SyntaxVisitor {
    private(set) var symbols: [SymbolNode] = []
    private(set) var references: [RawReference] = []
    private(set) var imports: [String] = []
    private(set) var localTypes: [String: [String: String]] = [:]

    private let path: String
    private let fileHash: String
    private let module: String?
    private let converter: SourceLocationConverter

    /// Enclosing type names, for qualified names and `self` resolution.
    private var containerStack: [String] = []
    /// Enclosing symbols, so a reference knows which declaration it sits in.
    private var symbolStack: [SymbolNode] = []
    /// True while inside a protocol body, making members requirements.
    private var protocolDepth = 0
    /// Call expressions already accounted for, so their callee is not double-counted
    /// as a plain member access.
    private var consumedCallees: Set<SyntaxIdentifier> = []

    /// Whether each open extension pushed a symbol that must be popped.
    private var extensionPushedSymbol: [Bool] = []

    init(path: String, fileHash: String, module: String?, converter: SourceLocationConverter) {
        self.path = path
        self.fileHash = fileHash
        self.module = module
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Imports

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.path.map(\.name.text).joined(separator: ".")
        if !name.isEmpty {
            imports.append(name)
        }
        return .skipChildren
    }

    // MARK: - Type declarations

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        pushType(name: node.name.text, kind: .type, node: node, inheritance: node.inheritanceClause)
        return .visitChildren
    }

    override func visitPost(_: StructDeclSyntax) {
        popType()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        pushType(name: node.name.text, kind: .type, node: node, inheritance: node.inheritanceClause)
        return .visitChildren
    }

    override func visitPost(_: ClassDeclSyntax) {
        popType()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        pushType(name: node.name.text, kind: .type, node: node, inheritance: node.inheritanceClause)
        return .visitChildren
    }

    override func visitPost(_: ActorDeclSyntax) {
        popType()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        pushType(name: node.name.text, kind: .type, node: node, inheritance: node.inheritanceClause)
        return .visitChildren
    }

    override func visitPost(_: EnumDeclSyntax) {
        popType()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        protocolDepth += 1
        pushType(
            name: node.name.text,
            kind: .protocolDecl,
            node: node,
            inheritance: node.inheritanceClause
        )
        return .visitChildren
    }

    override func visitPost(_: ProtocolDeclSyntax) {
        popType()
        protocolDepth -= 1
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.extendedType.trimmedDescription
        containerStack.append(name)

        // `extension Foo: Bar` is the most common way Swift declares conformance, and
        // an extension is always at file scope — so attributing it to whatever symbol
        // happened to be parsed last silently credited an unrelated declaration and
        // left protocol-witness fanout with nothing to fan out to. Always attribute
        // the conformance to the extended type itself.
        if node.inheritanceClause != nil {
            let symbol = makeSymbol(
                SymbolSpec(
                    name: name,
                    kind: .type,
                    argumentLabels: nil,
                    arity: 0,
                    modifiers: node.modifiers
                ),
                node: node
            )
            symbols.append(symbol)
            recordInheritance(node.inheritanceClause, from: symbol, container: name)
            // Members of the extension belong to the extended type.
            symbolStack.append(symbol)
            extensionPushedSymbol.append(true)
        } else {
            extensionPushedSymbol.append(false)
        }

        return .visitChildren
    }

    override func visitPost(_: ExtensionDeclSyntax) {
        containerStack.removeLast()
        if extensionPushedSymbol.popLast() == true, !symbolStack.isEmpty {
            symbolStack.removeLast()
        }
    }

    // MARK: - Members

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let labels = argumentLabels(of: node.signature.parameterClause)
        let symbol = makeSymbol(
            SymbolSpec(
                name: node.name.text,
                kind: containerStack.isEmpty ? .function : .method,
                argumentLabels: labels,
                arity: node.signature.parameterClause.parameters.count,
                modifiers: node.modifiers
            ),
            node: node
        )
        pushSymbol(symbol)
        recordParameterTypes(node.signature.parameterClause, in: symbol)
        return .visitChildren
    }

    override func visitPost(_: FunctionDeclSyntax) {
        popSymbol()
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let symbol = makeSymbol(
            SymbolSpec(
                name: "init",
                kind: .initializer,
                argumentLabels: argumentLabels(of: node.signature.parameterClause),
                arity: node.signature.parameterClause.parameters.count,
                modifiers: node.modifiers
            ),
            node: node
        )
        pushSymbol(symbol)
        recordParameterTypes(node.signature.parameterClause, in: symbol)
        return .visitChildren
    }

    override func visitPost(_: InitializerDeclSyntax) {
        popSymbol()
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            let name = pattern.identifier.text

            // Record the declared type so a later `name.method()` can be resolved to
            // that type's member. Swift's habit of declaring dependencies as annotated
            // stored properties makes this the highest-yield resolution rule available
            // from pure syntax — no type checker required.
            if let annotation = binding.typeAnnotation {
                recordLocalType(name: name, type: annotation.type.trimmedDescription)
            } else if let initializer = binding.initializer,
                      let call = initializer.value.as(FunctionCallExprSyntax.self),
                      let callee = call.calledExpression.as(DeclReferenceExprSyntax.self),
                      callee.baseName.text.first?.isUppercase == true
            {
                // `let x = Foo(...)` types x as Foo.
                recordLocalType(name: name, type: callee.baseName.text)
            }

            // Top-level and member properties become symbols; locals inside function
            // bodies exist purely to type receivers. A binding is a member when the
            // innermost enclosing symbol is a type.
            let enclosingIsType = symbolStack.last?.kind == .type
                || symbolStack.last?.kind == .protocolDecl
            if symbolStack.isEmpty || enclosingIsType {
                let symbol = makeSymbol(
                    SymbolSpec(
                        name: name,
                        kind: .property,
                        argumentLabels: nil,
                        arity: 0,
                        modifiers: node.modifiers
                    ),
                    node: node
                )
                symbols.append(symbol)
            }
        }
        return .visitChildren
    }

    // MARK: - References

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let labels = node.arguments
            .map { $0.label?.text ?? "_" }
            .joined(separator: ":")
        let arity = node.arguments.count + (node.trailingClosure == nil ? 0 : 1)

        if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
            consumedCallees.insert(member.id)
            record(
                ReferenceSpec(
                    name: member.declName.baseName.text,
                    kind: .calls,
                    receiver: member.base?.trimmedDescription,
                    labels: labels.isEmpty ? nil : labels,
                    arity: arity
                ),
                node: node
            )
        } else if let callee = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            consumedCallees.insert(callee.id)
            let name = callee.baseName.text
            // A capitalized callee is a constructor, which is a different relationship
            // from calling a free function.
            record(
                ReferenceSpec(
                    name: name,
                    kind: name.first?.isUppercase == true ? .initializes : .calls,
                    receiver: nil,
                    labels: labels.isEmpty ? nil : labels,
                    arity: arity
                ),
                node: node
            )
        }
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        // Skip callees already recorded as calls; what remains is property access.
        guard !consumedCallees.contains(node.id) else { return .visitChildren }
        record(
            ReferenceSpec(
                name: node.declName.baseName.text,
                kind: .references,
                receiver: node.base?.trimmedDescription,
                labels: nil,
                arity: -1
            ),
            node: node
        )
        return .visitChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        record(
            ReferenceSpec(
                name: node.name.text,
                kind: .references,
                receiver: nil,
                labels: nil,
                arity: -1
            ),
            node: node
        )
        return .visitChildren
    }

    // MARK: - Helpers

    private func pushType(
        name: String,
        kind: SymbolKind,
        node: some SyntaxProtocol,
        inheritance: InheritanceClauseSyntax?
    ) {
        let symbol = makeSymbol(
            SymbolSpec(
                name: name,
                kind: kind,
                argumentLabels: nil,
                arity: 0,
                modifiers: nil
            ),
            node: node
        )
        symbols.append(symbol)
        recordInheritance(inheritance, from: symbol, container: name)
        containerStack.append(name)
        symbolStack.append(symbol)
    }

    private func popType() {
        if !containerStack.isEmpty {
            containerStack.removeLast()
        }
        if !symbolStack.isEmpty {
            symbolStack.removeLast()
        }
    }

    private func pushSymbol(_ symbol: SymbolNode) {
        symbols.append(symbol)
        symbolStack.append(symbol)
    }

    private func popSymbol() {
        if !symbolStack.isEmpty {
            symbolStack.removeLast()
        }
    }

    private struct SymbolSpec {
        let name: String
        let kind: SymbolKind
        let argumentLabels: String?
        let arity: Int
        let modifiers: DeclModifierListSyntax?
    }

    private func makeSymbol(_ spec: SymbolSpec, node: some SyntaxProtocol) -> SymbolNode {
        let name = spec.name
        let kind = spec.kind
        let argumentLabels = spec.argumentLabels
        let arity = spec.arity
        let modifiers = spec.modifiers
        let start = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
        let end = converter.location(for: node.endPosition).line
        let container = containerStack.last
        let qualified = container.map { "\($0).\(name)" } ?? name

        let modifierNames = modifiers?.map(\.name.text) ?? []
        let access = modifierNames.first {
            ["public", "package", "internal", "fileprivate", "private", "open"].contains($0)
        }

        return SymbolNode(
            id: SymbolNode.makeID(SymbolNode.Identity(
                path: path,
                container: container,
                name: name,
                kind: kind,
                argumentLabels: argumentLabels,
                isStatic: modifierNames.contains("static") || modifierNames.contains("class")
            )),
            name: name,
            qualifiedName: qualified,
            container: container,
            module: module,
            kind: kind,
            argumentLabels: argumentLabels,
            arity: arity,
            isStatic: modifierNames.contains("static") || modifierNames.contains("class"),
            isRequirement: protocolDepth > 0,
            isOverride: modifierNames.contains("override"),
            access: access,
            path: path,
            startLine: start,
            endLine: end,
            chunkID: nil,
            fileHash: fileHash
        )
    }

    private struct ReferenceSpec {
        let name: String
        let kind: EdgeKind
        let receiver: String?
        let labels: String?
        let arity: Int
    }

    private func record(_ spec: ReferenceSpec, node: some SyntaxProtocol) {
        let name = spec.name
        let kind = spec.kind
        let receiver = spec.receiver
        let labels = spec.labels
        let arity = spec.arity
        guard !name.isEmpty,
              name.count > 1,
              !SwiftGraphFactsExtractor.ignoredNames.contains(name),
              let enclosing = symbolStack.last
        else {
            return
        }

        references.append(RawReference(
            name: name,
            kind: kind,
            receiver: receiver.map { String($0.prefix(64)) },
            argumentLabels: labels,
            arity: arity,
            line: converter.location(for: node.positionAfterSkippingLeadingTrivia).line,
            enclosingSymbolID: enclosing.id
        ))
    }

    private func recordInheritance(
        _ clause: InheritanceClauseSyntax?,
        from symbol: SymbolNode,
        container: String
    ) {
        guard let clause else { return }
        for inherited in clause.inheritedTypes {
            let name = inherited.type.trimmedDescription
            guard !name.isEmpty else { continue }
            // Swift syntax alone cannot tell a superclass from a protocol, so both are
            // recorded as `conforms`; the resolver upgrades to `inherits` once it knows
            // the target is a class.
            references.append(RawReference(
                name: name,
                kind: .conforms,
                receiver: container,
                argumentLabels: nil,
                arity: -1,
                line: symbol.startLine,
                enclosingSymbolID: symbol.id
            ))
        }
    }

    private func recordLocalType(name: String, type: String) {
        guard let enclosing = symbolStack.last else { return }
        // Strip optionality and existential syntax so the name matches a declaration.
        let cleaned = type
            .replacingOccurrences(of: "any ", with: "")
            .replacingOccurrences(of: "some ", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "?!"))
        localTypes[enclosing.id, default: [:]][name] = cleaned
    }

    private func recordParameterTypes(_ clause: FunctionParameterClauseSyntax, in symbol: SymbolNode) {
        for parameter in clause.parameters {
            let name = (parameter.secondName ?? parameter.firstName).text
            guard name != "_" else { continue }
            let cleaned = parameter.type.trimmedDescription
                .replacingOccurrences(of: "any ", with: "")
                .replacingOccurrences(of: "some ", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "?!"))
            localTypes[symbol.id, default: [:]][name] = cleaned
        }
    }

    private func argumentLabels(of clause: FunctionParameterClauseSyntax) -> String? {
        let labels = clause.parameters.map(\.firstName.text)
        return labels.isEmpty ? nil : labels.joined(separator: ":")
    }
}
