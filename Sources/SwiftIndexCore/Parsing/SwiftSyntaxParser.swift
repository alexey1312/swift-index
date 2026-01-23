// MARK: - SwiftSyntaxParser

import Crypto
import Foundation
import SwiftParser
import SwiftSyntax

/// A parser for Swift source files using SwiftSyntax.
///
/// This parser extracts code chunks from Swift files by walking the AST
/// and identifying declarations such as functions, classes, structs, enums,
/// protocols, extensions, actors, and macros.
public struct SwiftSyntaxParser: Parser, Sendable {
    // MARK: - Parser Protocol

    public var supportedExtensions: Set<String> {
        ["swift"]
    }

    public init() {}

    public func parse(content: String, path: String) -> ParseResult {
        guard !content.isEmpty else {
            return .failure(.emptyContent)
        }

        let fileHash = computeHash(content)
        let sourceFile = SwiftParser.Parser.parse(source: content)

        let visitor = DeclarationVisitor(
            content: content,
            path: path,
            fileHash: fileHash
        )
        visitor.walk(sourceFile)

        return .success(visitor.chunks)
    }

    // MARK: - Private Helpers

    private func computeHash(_ content: String) -> String {
        let data = Data(content.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - DeclarationVisitor

/// A syntax visitor that extracts code chunks from Swift declarations.
private final class DeclarationVisitor: SyntaxVisitor {
    let content: String
    let path: String
    let fileHash: String
    let lines: [Substring]
    private(set) var chunks: [CodeChunk] = []

    /// Stack of parent type names for nested type context.
    private var typeStack: [String] = []

    init(content: String, path: String, fileHash: String) {
        self.content = content
        self.path = path
        self.fileHash = fileHash
        lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Functions

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let kind: ChunkKind = typeStack.isEmpty ? .function : .method
        let docComment = extractDocComment(for: node)
        let signature = buildFunctionSignature(node)

        addChunk(
            node: node,
            name: name,
            kind: kind,
            signature: signature,
            docComment: docComment
        )

        return .visitChildren
    }

    // MARK: - Initializers

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = "init"
        let docComment = extractDocComment(for: node)
        let signature = buildInitializerSignature(node)

        addChunk(
            node: node,
            name: name,
            kind: .initializer,
            signature: signature,
            docComment: docComment
        )

        return .visitChildren
    }

    // MARK: - Deinitializers

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = "deinit"
        let docComment = extractDocComment(for: node)

        addChunk(
            node: node,
            name: name,
            kind: .deinitializer,
            signature: "deinit",
            docComment: docComment
        )

        return .visitChildren
    }

    // MARK: - Subscripts

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = "subscript"
        let docComment = extractDocComment(for: node)
        let signature = buildSubscriptSignature(node)

        addChunk(
            node: node,
            name: name,
            kind: .subscript,
            signature: signature,
            docComment: docComment
        )

        return .visitChildren
    }

    // MARK: - Classes

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let docComment = extractDocComment(for: node)
        let signature = buildClassSignature(node)

        addChunk(
            node: node,
            name: name,
            kind: .class,
            signature: signature,
            docComment: docComment
        )

        typeStack.append(name)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        _ = typeStack.popLast()
    }

    // MARK: - Structs

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let docComment = extractDocComment(for: node)
        let signature = buildStructSignature(node)

        addChunk(
            node: node,
            name: name,
            kind: .struct,
            signature: signature,
            docComment: docComment
        )

        typeStack.append(name)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        _ = typeStack.popLast()
    }

    // MARK: - Enums

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let docComment = extractDocComment(for: node)
        let signature = buildEnumSignature(node)

        addChunk(
            node: node,
            name: name,
            kind: .enum,
            signature: signature,
            docComment: docComment
        )

        typeStack.append(name)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        _ = typeStack.popLast()
    }

    // MARK: - Protocols

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let docComment = extractDocComment(for: node)
        let signature = buildProtocolSignature(node)

        addChunk(
            node: node,
            name: name,
            kind: .protocol,
            signature: signature,
            docComment: docComment
        )

        typeStack.append(name)
        return .visitChildren
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        _ = typeStack.popLast()
    }

    // MARK: - Extensions

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let extendedType = node.extendedType.trimmedDescription
        let name = extendedType
        let docComment = extractDocComment(for: node)
        let signature = buildExtensionSignature(node)

        addChunk(
            node: node,
            name: name,
            kind: .extension,
            signature: signature,
            docComment: docComment
        )

        typeStack.append(extendedType)
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        _ = typeStack.popLast()
    }

    // MARK: - Actors

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let docComment = extractDocComment(for: node)
        let signature = buildActorSignature(node)

        addChunk(
            node: node,
            name: name,
            kind: .actor,
            signature: signature,
            docComment: docComment
        )

        typeStack.append(name)
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        _ = typeStack.popLast()
    }

    // MARK: - Macros

    override func visit(_ node: MacroDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let docComment = extractDocComment(for: node)
        let signature = buildMacroSignature(node)

        addChunk(
            node: node,
            name: name,
            kind: .macro,
            signature: signature,
            docComment: docComment
        )

        return .visitChildren
    }

    // MARK: - Type Aliases

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let docComment = extractDocComment(for: node)
        let signature = "typealias \(name) = \(node.initializer.value.trimmedDescription)"

        addChunk(
            node: node,
            name: name,
            kind: .typealias,
            signature: signature,
            docComment: docComment
        )

        return .visitChildren
    }

    // MARK: - Variables (top-level or type properties)

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Only capture top-level or type-level properties, not local variables
        guard let parent = node.parent else {
            return .visitChildren
        }

        let isTopLevelOrMember = parent.is(MemberBlockItemSyntax.self) ||
            parent.is(CodeBlockItemSyntax.self) ||
            parent.is(SourceFileSyntax.self)

        guard isTopLevelOrMember else {
            return .visitChildren
        }

        for binding in node.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }

            let name = pattern.identifier.text
            let kind: ChunkKind = node.bindingSpecifier.tokenKind == .keyword(.let) ? .constant : .variable
            let docComment = extractDocComment(for: node)
            let signature = buildVariableSignature(node, binding: binding)

            addChunk(
                node: node,
                name: name,
                kind: kind,
                signature: signature,
                docComment: docComment
            )
        }

        return .visitChildren
    }

    // MARK: - Chunk Creation

    private func addChunk(
        node: some SyntaxProtocol,
        name: String,
        kind: ChunkKind,
        signature: String,
        docComment: String?
    ) {
        let locationConverter = SourceLocationConverter(
            fileName: path,
            tree: node.root
        )

        let startLocation = locationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let endLocation = locationConverter.location(for: node.endPositionBeforeTrailingTrivia)

        let startLine = startLocation.line
        let endLine = endLocation.line

        // Extract the full source text for this node
        let sourceText = extractSourceText(for: node)

        // Build qualified name with parent context
        let qualifiedName = buildQualifiedName(name)

        // Build breadcrumb for hierarchy context
        let breadcrumb = buildBreadcrumb(name)

        // Generate unique chunk ID
        let chunkId = generateChunkId(
            path: path,
            name: qualifiedName,
            kind: kind,
            startLine: startLine
        )

        // Collect symbols
        var symbols = [qualifiedName]
        if qualifiedName != name {
            symbols.append(name)
        }

        let chunk = CodeChunk(
            id: chunkId,
            path: path,
            content: sourceText,
            startLine: startLine,
            endLine: endLine,
            kind: kind,
            symbols: symbols,
            references: extractReferences(from: node),
            fileHash: fileHash,
            docComment: docComment,
            signature: signature,
            breadcrumb: breadcrumb
        )

        chunks.append(chunk)
    }

    // MARK: - Breadcrumb Building

    private func buildBreadcrumb(_ name: String) -> String? {
        if typeStack.isEmpty {
            return nil
        }
        return (typeStack + [name]).joined(separator: " > ")
    }

    // MARK: - Source Text Extraction

    private func extractSourceText(for node: some SyntaxProtocol) -> String {
        // Include leading trivia (doc comments) in the source text
        node.description
    }

    // MARK: - Doc Comment Extraction

    private func extractDocComment(for node: some SyntaxProtocol) -> String? {
        let trivia = node.leadingTrivia
        var docLines: [String] = []

        for piece in trivia {
            switch piece {
            case let .docLineComment(text):
                // Strip "///" prefix
                let content = text.dropFirst(3)
                docLines.append(String(content).trimmingCharacters(in: .whitespaces))

            case let .docBlockComment(text):
                // Strip "/**" and "*/" and handle intermediate lines
                var cleaned = text
                if cleaned.hasPrefix("/**") {
                    cleaned = String(cleaned.dropFirst(3))
                }
                if cleaned.hasSuffix("*/") {
                    cleaned = String(cleaned.dropLast(2))
                }
                let lines = cleaned.split(separator: "\n", omittingEmptySubsequences: false)
                for line in lines {
                    var lineStr = String(line).trimmingCharacters(in: .whitespaces)
                    if lineStr.hasPrefix("*") {
                        lineStr = String(lineStr.dropFirst()).trimmingCharacters(in: .whitespaces)
                    }
                    docLines.append(lineStr)
                }

            default:
                break
            }
        }

        let result = docLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    // MARK: - Qualified Name Building

    private func buildQualifiedName(_ name: String) -> String {
        if typeStack.isEmpty {
            return name
        }
        return (typeStack + [name]).joined(separator: ".")
    }

    // MARK: - Chunk ID Generation

    private func generateChunkId(path: String, name: String, kind: ChunkKind, startLine: Int) -> String {
        let components = [path, name, kind.rawValue, String(startLine)]
        let joined = components.joined(separator: ":")
        let data = Data(joined.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Reference Extraction

    private func extractReferences(from node: some SyntaxProtocol) -> [String] {
        var references: [String] = []
        let referenceVisitor = ReferenceVisitor()
        referenceVisitor.walk(node)
        references = Array(referenceVisitor.references)
        return references
    }

    // MARK: - Signature Builders

    private func buildFunctionSignature(_ node: FunctionDeclSyntax) -> String {
        var parts: [String] = []

        // Modifiers
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }

        parts.append("func")
        parts.append(node.name.text)

        // Generic parameters
        if let genericParams = node.genericParameterClause {
            parts.append(genericParams.trimmedDescription)
        }

        // Parameters
        parts.append(node.signature.parameterClause.trimmedDescription)

        // Async/throws
        if let effectSpecifiers = node.signature.effectSpecifiers {
            if effectSpecifiers.asyncSpecifier != nil {
                parts.append("async")
            }
            if let throwsClause = effectSpecifiers.throwsClause {
                parts.append(throwsClause.trimmedDescription)
            }
        }

        // Return type
        if let returnClause = node.signature.returnClause {
            parts.append(returnClause.trimmedDescription)
        }

        // Generic where clause
        if let whereClause = node.genericWhereClause {
            parts.append(whereClause.trimmedDescription)
        }

        return parts.joined(separator: " ")
    }

    private func buildInitializerSignature(_ node: InitializerDeclSyntax) -> String {
        var parts: [String] = []

        // Modifiers
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }

        // init with optional ?/!
        var initKeyword = "init"
        if let optionalMark = node.optionalMark {
            initKeyword += optionalMark.text
        }
        parts.append(initKeyword)

        // Generic parameters
        if let genericParams = node.genericParameterClause {
            parts.append(genericParams.trimmedDescription)
        }

        // Parameters
        parts.append(node.signature.parameterClause.trimmedDescription)

        // Async/throws
        if let effectSpecifiers = node.signature.effectSpecifiers {
            if effectSpecifiers.asyncSpecifier != nil {
                parts.append("async")
            }
            if let throwsClause = effectSpecifiers.throwsClause {
                parts.append(throwsClause.trimmedDescription)
            }
        }

        return parts.joined(separator: " ")
    }

    private func buildSubscriptSignature(_ node: SubscriptDeclSyntax) -> String {
        var parts: [String] = []

        // Modifiers
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }

        parts.append("subscript")

        // Generic parameters
        if let genericParams = node.genericParameterClause {
            parts.append(genericParams.trimmedDescription)
        }

        // Parameters
        parts.append(node.parameterClause.trimmedDescription)

        // Return type
        parts.append(node.returnClause.trimmedDescription)

        return parts.joined(separator: " ")
    }

    private func buildClassSignature(_ node: ClassDeclSyntax) -> String {
        var parts: [String] = []

        // Modifiers
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }

        parts.append("class")
        parts.append(node.name.text)

        // Generic parameters
        if let genericParams = node.genericParameterClause {
            parts.append(genericParams.trimmedDescription)
        }

        // Inheritance
        if let inheritanceClause = node.inheritanceClause {
            parts.append(inheritanceClause.trimmedDescription)
        }

        // Generic where clause
        if let whereClause = node.genericWhereClause {
            parts.append(whereClause.trimmedDescription)
        }

        return parts.joined(separator: " ")
    }

    private func buildStructSignature(_ node: StructDeclSyntax) -> String {
        var parts: [String] = []

        // Modifiers
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }

        parts.append("struct")
        parts.append(node.name.text)

        // Generic parameters
        if let genericParams = node.genericParameterClause {
            parts.append(genericParams.trimmedDescription)
        }

        // Inheritance
        if let inheritanceClause = node.inheritanceClause {
            parts.append(inheritanceClause.trimmedDescription)
        }

        // Generic where clause
        if let whereClause = node.genericWhereClause {
            parts.append(whereClause.trimmedDescription)
        }

        return parts.joined(separator: " ")
    }

    private func buildEnumSignature(_ node: EnumDeclSyntax) -> String {
        var parts: [String] = []

        // Modifiers
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }

        parts.append("enum")
        parts.append(node.name.text)

        // Generic parameters
        if let genericParams = node.genericParameterClause {
            parts.append(genericParams.trimmedDescription)
        }

        // Inheritance
        if let inheritanceClause = node.inheritanceClause {
            parts.append(inheritanceClause.trimmedDescription)
        }

        // Generic where clause
        if let whereClause = node.genericWhereClause {
            parts.append(whereClause.trimmedDescription)
        }

        return parts.joined(separator: " ")
    }

    private func buildProtocolSignature(_ node: ProtocolDeclSyntax) -> String {
        var parts: [String] = []

        // Modifiers
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }

        parts.append("protocol")
        parts.append(node.name.text)

        // Primary associated types
        if let primaryAssocTypes = node.primaryAssociatedTypeClause {
            parts.append(primaryAssocTypes.trimmedDescription)
        }

        // Inheritance
        if let inheritanceClause = node.inheritanceClause {
            parts.append(inheritanceClause.trimmedDescription)
        }

        return parts.joined(separator: " ")
    }

    private func buildExtensionSignature(_ node: ExtensionDeclSyntax) -> String {
        var parts: [String] = []

        // Modifiers
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }

        parts.append("extension")
        parts.append(node.extendedType.trimmedDescription)

        // Inheritance
        if let inheritanceClause = node.inheritanceClause {
            parts.append(inheritanceClause.trimmedDescription)
        }

        // Generic where clause
        if let whereClause = node.genericWhereClause {
            parts.append(whereClause.trimmedDescription)
        }

        return parts.joined(separator: " ")
    }

    private func buildActorSignature(_ node: ActorDeclSyntax) -> String {
        var parts: [String] = []

        // Modifiers
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }

        parts.append("actor")
        parts.append(node.name.text)

        // Generic parameters
        if let genericParams = node.genericParameterClause {
            parts.append(genericParams.trimmedDescription)
        }

        // Inheritance
        if let inheritanceClause = node.inheritanceClause {
            parts.append(inheritanceClause.trimmedDescription)
        }

        // Generic where clause
        if let whereClause = node.genericWhereClause {
            parts.append(whereClause.trimmedDescription)
        }

        return parts.joined(separator: " ")
    }

    private func buildMacroSignature(_ node: MacroDeclSyntax) -> String {
        var parts: [String] = []

        // Modifiers
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }

        parts.append("macro")
        parts.append(node.name.text)

        // Generic parameters
        if let genericParams = node.genericParameterClause {
            parts.append(genericParams.trimmedDescription)
        }

        // Signature
        parts.append(node.signature.parameterClause.trimmedDescription)

        // Return type
        if let returnClause = node.signature.returnClause {
            parts.append(returnClause.trimmedDescription)
        }

        return parts.joined(separator: " ")
    }

    private func buildVariableSignature(
        _ node: VariableDeclSyntax,
        binding: PatternBindingSyntax
    ) -> String {
        var parts: [String] = []

        // Modifiers
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }

        // let or var
        parts.append(node.bindingSpecifier.text)

        // Pattern (name)
        parts.append(binding.pattern.trimmedDescription)

        // Type annotation
        if let typeAnnotation = binding.typeAnnotation {
            parts.append(typeAnnotation.trimmedDescription)
        }

        return parts.joined(separator: " ")
    }
}

// MARK: - ReferenceVisitor

/// A visitor that collects type and identifier references from syntax nodes.
private final class ReferenceVisitor: SyntaxVisitor {
    var references: Set<String> = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        references.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        references.insert(node.baseName.text)
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        references.insert(node.declName.baseName.text)
        return .visitChildren
    }
}
