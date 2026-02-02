// MARK: - Parse Tree Visualizer

import Foundation
import SwiftParser
import SwiftSyntax

/// Options for AST visualization.
public struct ParseTreeOptions: Sendable {
    /// Maximum depth to traverse (nil = unlimited).
    public let maxDepth: Int?

    /// Filter by node kinds (nil = all kinds).
    public let kindFilter: Set<String>?

    /// Whether to expand children nodes.
    public let expandChildren: Bool

    /// Glob pattern for directory mode (default: "**/*.swift").
    public let pattern: String?

    public init(
        maxDepth: Int? = nil,
        kindFilter: Set<String>? = nil,
        expandChildren: Bool = true,
        pattern: String? = nil
    ) {
        self.maxDepth = maxDepth
        self.kindFilter = kindFilter
        self.expandChildren = expandChildren
        self.pattern = pattern
    }

    /// Default options for visualization.
    public static let `default` = ParseTreeOptions()
}

/// Visualizes Swift AST structure.
///
/// A stateless, Sendable struct that parses Swift source files and produces
/// `ASTNode` trees for visualization. Uses SwiftSyntax for accurate parsing.
public struct ParseTreeVisualizer: Sendable {
    public init() {}

    // MARK: - Single File API

    /// Visualize AST structure for a single file's content.
    ///
    /// - Parameters:
    ///   - content: Swift source code content.
    ///   - path: File path (for metadata).
    ///   - options: Visualization options.
    /// - Returns: Parse tree result with AST nodes.
    public func visualize(
        content: String,
        path: String,
        options: ParseTreeOptions = .default
    ) -> ParseTreeResult {
        guard !content.isEmpty else {
            return ParseTreeResult(
                nodes: [],
                totalNodes: 0,
                maxDepth: 0,
                path: path,
                language: detectLanguage(from: path)
            )
        }

        // Parse with SwiftSyntax
        let sourceFile = SwiftParser.Parser.parse(source: content)

        // Create visitor and walk AST
        let visitor = ASTVisitor(options: options)
        visitor.walk(sourceFile)

        let nodes = visitor.rootNodes
        let totalNodes = countNodes(nodes)
        let maxDepth = calculateMaxDepth(nodes)

        return ParseTreeResult(
            nodes: nodes,
            totalNodes: totalNodes,
            maxDepth: maxDepth,
            path: path,
            language: detectLanguage(from: path)
        )
    }

    /// Visualize AST structure from a file path.
    ///
    /// - Parameters:
    ///   - filePath: Path to the Swift file.
    ///   - options: Visualization options.
    /// - Returns: Parse tree result.
    /// - Throws: If file cannot be read.
    public func visualizeFile(
        at filePath: String,
        options: ParseTreeOptions = .default
    ) throws -> ParseTreeResult {
        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        return visualize(content: content, path: filePath, options: options)
    }

    // MARK: - Directory API

    /// Visualize AST for all matching files in a directory.
    ///
    /// - Parameters:
    ///   - directoryPath: Path to the directory.
    ///   - options: Visualization options (includes glob pattern).
    /// - Returns: Batch result with all file results.
    /// - Throws: If directory cannot be read.
    public func visualizeDirectory(
        at directoryPath: String,
        options: ParseTreeOptions = .default
    ) async throws -> ParseTreeBatchResult {
        let pattern = options.pattern ?? "**/*.swift"
        let files = try findMatchingFiles(in: directoryPath, pattern: pattern)

        var results: [ParseTreeResult] = []
        var totalNodes = 0
        var maxDepth = 0

        for filePath in files {
            do {
                let result = try visualizeFile(at: filePath, options: options)
                results.append(result)
                totalNodes += result.totalNodes
                maxDepth = max(maxDepth, result.maxDepth)
            } catch {
                // Skip files that can't be read
                continue
            }
        }

        return ParseTreeBatchResult(
            files: results,
            totalFiles: results.count,
            totalNodes: totalNodes,
            maxDepth: maxDepth,
            rootPath: directoryPath
        )
    }

    // MARK: - Output Formatters (Single File)

    /// Format result as TOON (Token-Optimized Object Notation).
    public func formatTOON(_ result: ParseTreeResult) -> String {
        var output = "ast{path,lang,nodes,depth}:\n"
        let path = escapeString(result.path)
        output += "  \"\(path)\",\"\(result.language)\",\(result.totalNodes),\(result.maxDepth)\n\n"

        if result.nodes.isEmpty {
            return output
        }

        output += "tree[\(result.totalNodes)]{d,k,name,l,sig}:\n"
        output += formatNodesTOON(result.nodes)

        return output
    }

    /// Format result as human-readable tree view.
    public func formatHuman(_ result: ParseTreeResult) -> String {
        let fileName = (result.path as NSString).lastPathComponent
        var output = "\(fileName) (\(result.language)) — \(result.totalNodes) nodes\n"
        output += String(repeating: "─", count: 40) + "\n"

        if result.nodes.isEmpty {
            output += "(empty)\n"
            return output
        }

        for node in result.nodes {
            output += formatNodeHuman(node, prefix: "", isLast: true)
        }

        return output
    }

    /// Format result as JSON.
    public func formatJSON(_ result: ParseTreeResult) throws -> String {
        let data = try JSONCodec.encodePrettySorted(result)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - Output Formatters (Batch)

    /// Format batch result as TOON.
    public func formatTOON(_ result: ParseTreeBatchResult) -> String {
        var output = "batch{root,files,nodes,depth}:\n"
        let rootPath = escapeString(result.rootPath)
        output += "  \"\(rootPath)\",\(result.totalFiles),\(result.totalNodes),\(result.maxDepth)\n\n"

        for (index, fileResult) in result.files.enumerated() {
            output += "file[\(index)]{path,nodes,depth}:\n"
            output += "  \"\(escapeString(fileResult.path))\",\(fileResult.totalNodes),\(fileResult.maxDepth)\n"

            if !fileResult.nodes.isEmpty {
                output += "tree[\(fileResult.totalNodes)]{d,k,name,l}:\n"
                output += formatNodesTOON(fileResult.nodes, includeSignature: false)
            }
            output += "\n"
        }

        return output
    }

    /// Format batch result as human-readable.
    public func formatHuman(_ result: ParseTreeBatchResult) -> String {
        var output = "\(result.rootPath) — \(result.totalFiles) files, \(result.totalNodes) nodes\n"
        output += String(repeating: "═", count: 50) + "\n\n"

        for fileResult in result.files {
            output += "\(fileResult.path) (\(fileResult.totalNodes) nodes)\n"
            output += String(repeating: "─", count: 40) + "\n"

            if fileResult.nodes.isEmpty {
                output += "(empty)\n"
            } else {
                for node in fileResult.nodes {
                    output += formatNodeHuman(node, prefix: "", isLast: true)
                }
            }
            output += "\n"
        }

        return output
    }

    /// Format batch result as JSON.
    public func formatJSON(_ result: ParseTreeBatchResult) throws -> String {
        let data = try JSONCodec.encodePrettySorted(result)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - Private Helpers

    private func countNodes(_ nodes: [ASTNode]) -> Int {
        var count = nodes.count
        for node in nodes {
            count += countNodes(node.children)
        }
        return count
    }

    private func calculateMaxDepth(_ nodes: [ASTNode]) -> Int {
        guard !nodes.isEmpty else { return 0 }
        var maxDepth = 0
        for node in nodes {
            let childMax = calculateMaxDepth(node.children)
            maxDepth = max(maxDepth, max(node.depth, childMax))
        }
        return maxDepth
    }

    private func formatNodesTOON(_ nodes: [ASTNode], includeSignature: Bool = true) -> String {
        var output = ""
        for node in nodes {
            output += formatNodeTOON(node, includeSignature: includeSignature)
        }
        return output
    }

    private func formatNodeTOON(_ node: ASTNode, includeSignature: Bool) -> String {
        var output = ""
        let name = node.name.map { "\"\(escapeString($0))\"" } ?? "~"
        let lines = node.startLine == node.endLine
            ? "[\(node.startLine)]"
            : "[\(node.startLine),\(node.endLine)]"

        if includeSignature {
            let sig = node.signature.map { "\"\(escapeString($0))\"" } ?? "~"
            output += "  \(node.depth),\"\(node.kind)\",\(name),\(lines),\(sig)\n"
        } else {
            output += "  \(node.depth),\"\(node.kind)\",\(name),\(lines)\n"
        }

        for child in node.children {
            output += formatNodeTOON(child, includeSignature: includeSignature)
        }
        return output
    }

    private func formatNodeHuman(_ node: ASTNode, prefix: String, isLast: Bool) -> String {
        var output = ""

        // Build the tree branch characters
        let connector = isLast ? "└── " : "├── "
        let childPrefix = prefix + (isLast ? "    " : "│   ")

        // Format the node line
        let lineRange = node.startLine == node.endLine
            ? "[\(node.startLine)]"
            : "[\(node.startLine)-\(node.endLine)]"

        if let signature = node.signature {
            output += prefix + connector + "\(signature) \(lineRange)\n"
        } else if let name = node.name {
            output += prefix + connector + "\(node.kind) \(name) \(lineRange)\n"
        } else {
            output += prefix + connector + "\(node.kind) \(lineRange)\n"
        }

        // Format children
        for (index, child) in node.children.enumerated() {
            let isLastChild = index == node.children.count - 1
            output += formatNodeHuman(child, prefix: childPrefix, isLast: isLastChild)
        }

        return output
    }

    private func escapeString(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func detectLanguage(from path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "m", "mm": return "objective-c"
        case "h": return "c-header"
        case "c": return "c"
        case "cpp", "cc", "cxx", "hpp": return "cpp"
        default: return "unknown"
        }
    }

    private func findMatchingFiles(in directory: String, pattern: String) throws -> [String] {
        let fileManager = FileManager.default
        let directoryURL = URL(fileURLWithPath: directory)

        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var matchingFiles: [String] = []
        let matcher = SyncGlobMatcher()

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true
            else {
                continue
            }

            // Get relative path for matching
            let fullPath = fileURL.path
            let relativePath = String(fullPath.dropFirst(directory.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            if matcher.matches(relativePath, pattern: pattern) {
                matchingFiles.append(fullPath)
            }
        }

        return matchingFiles.sorted()
    }
}

// MARK: - Synchronous Glob Matcher

/// A simple synchronous glob matcher for file filtering.
private struct SyncGlobMatcher {
    func matches(_ path: String, pattern: String) -> Bool {
        let regexPattern = globToRegex(pattern)
        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return false
        }
        let range = NSRange(path.startIndex..., in: path)
        return regex.firstMatch(in: path, range: range) != nil
    }

    private func globToRegex(_ pattern: String) -> String {
        // Handle **/*.ext pattern specially - should match files at any depth including root
        var processedPattern = pattern

        // Replace **/ at start with optional path prefix (matches zero or more directories)
        if processedPattern.hasPrefix("**/") {
            processedPattern = String(processedPattern.dropFirst(3))
            // The prefix can be empty (root) or any path
            let suffix = globToRegexCore(processedPattern)
            return "^(.*/)?" + suffix + "$"
        }

        return "^" + globToRegexCore(pattern) + "$"
    }

    private func globToRegexCore(_ pattern: String) -> String {
        pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "**/", with: "(.*/)?")
            .replacingOccurrences(of: "**", with: ".*")
            .replacingOccurrences(of: "*", with: "[^/]*")
            .replacingOccurrences(of: "?", with: ".")
    }
}

// MARK: - ASTVisitor

/// A syntax visitor that extracts AST nodes for visualization.
///
/// This is a non-Sendable class created locally in `visualize()` method,
/// following the pattern from `SwiftSyntaxParser.DeclarationVisitor`.
private final class ASTVisitor: SyntaxVisitor {
    let options: ParseTreeOptions
    private(set) var rootNodes: [ASTNode] = []

    /// Stack for building nested structure.
    private var nodeStack: [[ASTNode]] = [[]]

    /// Current depth in the AST.
    private var currentDepth: Int = 0

    init(options: ParseTreeOptions) {
        self.options = options
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Classes

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        return visitDeclaration(node, kind: "class", name: name) {
            buildClassSignature(node)
        }
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        popNode()
    }

    // MARK: - Structs

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        return visitDeclaration(node, kind: "struct", name: name) {
            buildStructSignature(node)
        }
    }

    override func visitPost(_ node: StructDeclSyntax) {
        popNode()
    }

    // MARK: - Enums

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        return visitDeclaration(node, kind: "enum", name: name) {
            buildEnumSignature(node)
        }
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        popNode()
    }

    // MARK: - Protocols

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        return visitDeclaration(node, kind: "protocol", name: name) {
            buildProtocolSignature(node)
        }
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        popNode()
    }

    // MARK: - Extensions

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.extendedType.trimmedDescription
        return visitDeclaration(node, kind: "extension", name: name) {
            buildExtensionSignature(node)
        }
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        popNode()
    }

    // MARK: - Actors

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        return visitDeclaration(node, kind: "actor", name: name) {
            buildActorSignature(node)
        }
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        popNode()
    }

    // MARK: - Functions

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let kind = currentDepth > 0 ? "method" : "function"
        return visitDeclaration(node, kind: kind, name: name) {
            buildFunctionSignature(node)
        }
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        popNode()
    }

    // MARK: - Initializers

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        visitDeclaration(node, kind: "init", name: "init") {
            buildInitializerSignature(node)
        }
    }

    override func visitPost(_ node: InitializerDeclSyntax) {
        popNode()
    }

    // MARK: - Deinitializers

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        visitDeclaration(node, kind: "deinit", name: "deinit") {
            "deinit"
        }
    }

    override func visitPost(_ node: DeinitializerDeclSyntax) {
        popNode()
    }

    // MARK: - Variables

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Only capture top-level or type-level properties
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
            let kind = node.bindingSpecifier.tokenKind == .keyword(.let) ? "constant" : "variable"
            let signature = buildVariableSignature(node, binding: binding)

            let location = getLocation(for: node)
            addLeafNode(kind: kind, name: name, location: location, signature: signature)
        }

        return .visitChildren
    }

    // MARK: - Subscripts

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        visitDeclaration(node, kind: "subscript", name: "subscript") {
            buildSubscriptSignature(node)
        }
    }

    override func visitPost(_ node: SubscriptDeclSyntax) {
        popNode()
    }

    // MARK: - Type Aliases

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let signature = "typealias \(name) = \(node.initializer.value.trimmedDescription)"
        let location = getLocation(for: node)
        addLeafNode(kind: "typealias", name: name, location: location, signature: signature)
        return .visitChildren
    }

    // MARK: - Macros

    override func visit(_ node: MacroDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        return visitDeclaration(node, kind: "macro", name: name) {
            buildMacroSignature(node)
        }
    }

    override func visitPost(_ node: MacroDeclSyntax) {
        popNode()
    }

    // MARK: - Private Helpers

    private func visitDeclaration(
        _ node: some SyntaxProtocol,
        kind: String,
        name: String,
        signature: () -> String
    ) -> SyntaxVisitorContinueKind {
        // Check depth limit
        if let maxDepth = options.maxDepth, currentDepth >= maxDepth {
            return .skipChildren
        }

        // Check kind filter - if filtered out, still visit children but don't create node
        let isFiltered = options.kindFilter.map { !$0.contains(kind) } ?? false

        let location = getLocation(for: node)

        // Push new level for children
        nodeStack.append([])
        currentDepth += 1

        // Store node info for building later (in visitPost)
        let nodeInfo = PendingNode(
            kind: kind,
            name: name,
            startLine: location.startLine,
            endLine: location.endLine,
            signature: isFiltered ? "" : signature(),
            includeNode: !isFiltered
        )
        pendingNodes.append(nodeInfo)

        return .visitChildren
    }

    private var pendingNodes: [PendingNode] = []

    private struct PendingNode {
        let kind: String
        let name: String
        let startLine: Int
        let endLine: Int
        let signature: String
        let includeNode: Bool
    }

    private func popNode() {
        guard let pending = pendingNodes.popLast() else { return }

        // Pop children
        let children = nodeStack.removeLast()
        currentDepth -= 1

        // If filtered out, promote children to parent level (or root)
        if !pending.includeNode {
            if currentDepth == 0 {
                rootNodes.append(contentsOf: children)
            } else {
                nodeStack[nodeStack.count - 1].append(contentsOf: children)
            }
            return
        }

        let node = ASTNode(
            kind: pending.kind,
            name: pending.name,
            startLine: pending.startLine,
            endLine: pending.endLine,
            signature: pending.signature,
            children: children,
            depth: currentDepth
        )

        // Add to parent's children or root
        // At depth 0, nodeStack has only the initial empty array
        if currentDepth == 0 {
            rootNodes.append(node)
        } else {
            nodeStack[nodeStack.count - 1].append(node)
        }
    }

    private func addLeafNode(
        kind: String,
        name: String,
        location: (startLine: Int, endLine: Int),
        signature: String
    ) {
        // Check kind filter
        if let filter = options.kindFilter, !filter.contains(kind) {
            return
        }

        let node = ASTNode(
            kind: kind,
            name: name,
            startLine: location.startLine,
            endLine: location.endLine,
            signature: signature,
            children: [],
            depth: currentDepth
        )

        if nodeStack.isEmpty {
            rootNodes.append(node)
        } else {
            nodeStack[nodeStack.count - 1].append(node)
        }
    }

    private func getLocation(for node: some SyntaxProtocol) -> (startLine: Int, endLine: Int) {
        let converter = SourceLocationConverter(fileName: "", tree: node.root)
        let start = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        let end = converter.location(for: node.endPositionBeforeTrailingTrivia)
        return (start.line, end.line)
    }

    // MARK: - Signature Builders

    private func buildFunctionSignature(_ node: FunctionDeclSyntax) -> String {
        var parts: [String] = []
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }
        parts.append("func")
        parts.append(node.name.text)
        if let genericParams = node.genericParameterClause {
            parts.append(genericParams.trimmedDescription)
        }
        parts.append(node.signature.parameterClause.trimmedDescription)
        if let effectSpecifiers = node.signature.effectSpecifiers {
            if effectSpecifiers.asyncSpecifier != nil {
                parts.append("async")
            }
            if let throwsClause = effectSpecifiers.throwsClause {
                parts.append(throwsClause.trimmedDescription)
            }
        }
        if let returnClause = node.signature.returnClause {
            parts.append(returnClause.trimmedDescription)
        }
        return parts.joined(separator: " ")
    }

    private func buildInitializerSignature(_ node: InitializerDeclSyntax) -> String {
        var parts: [String] = []
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }
        var initKeyword = "init"
        if let optionalMark = node.optionalMark {
            initKeyword += optionalMark.text
        }
        parts.append(initKeyword)
        if let genericParams = node.genericParameterClause {
            parts.append(genericParams.trimmedDescription)
        }
        parts.append(node.signature.parameterClause.trimmedDescription)
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
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }
        parts.append("subscript")
        if let genericParams = node.genericParameterClause {
            parts.append(genericParams.trimmedDescription)
        }
        parts.append(node.parameterClause.trimmedDescription)
        parts.append(node.returnClause.trimmedDescription)
        return parts.joined(separator: " ")
    }

    private func buildClassSignature(_ node: ClassDeclSyntax) -> String {
        var parts: [String] = []
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }
        parts.append("class")
        parts.append(node.name.text)
        if let genericParams = node.genericParameterClause {
            parts.append(genericParams.trimmedDescription)
        }
        if let inheritanceClause = node.inheritanceClause {
            parts.append(inheritanceClause.trimmedDescription)
        }
        return parts.joined(separator: " ")
    }

    private func buildStructSignature(_ node: StructDeclSyntax) -> String {
        var parts: [String] = []
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }
        parts.append("struct")
        parts.append(node.name.text)
        if let genericParams = node.genericParameterClause {
            parts.append(genericParams.trimmedDescription)
        }
        if let inheritanceClause = node.inheritanceClause {
            parts.append(inheritanceClause.trimmedDescription)
        }
        return parts.joined(separator: " ")
    }

    private func buildEnumSignature(_ node: EnumDeclSyntax) -> String {
        var parts: [String] = []
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }
        parts.append("enum")
        parts.append(node.name.text)
        if let genericParams = node.genericParameterClause {
            parts.append(genericParams.trimmedDescription)
        }
        if let inheritanceClause = node.inheritanceClause {
            parts.append(inheritanceClause.trimmedDescription)
        }
        return parts.joined(separator: " ")
    }

    private func buildProtocolSignature(_ node: ProtocolDeclSyntax) -> String {
        var parts: [String] = []
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }
        parts.append("protocol")
        parts.append(node.name.text)
        if let primaryAssocTypes = node.primaryAssociatedTypeClause {
            parts.append(primaryAssocTypes.trimmedDescription)
        }
        if let inheritanceClause = node.inheritanceClause {
            parts.append(inheritanceClause.trimmedDescription)
        }
        return parts.joined(separator: " ")
    }

    private func buildExtensionSignature(_ node: ExtensionDeclSyntax) -> String {
        var parts: [String] = []
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }
        parts.append("extension")
        parts.append(node.extendedType.trimmedDescription)
        if let inheritanceClause = node.inheritanceClause {
            parts.append(inheritanceClause.trimmedDescription)
        }
        if let whereClause = node.genericWhereClause {
            parts.append(whereClause.trimmedDescription)
        }
        return parts.joined(separator: " ")
    }

    private func buildActorSignature(_ node: ActorDeclSyntax) -> String {
        var parts: [String] = []
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }
        parts.append("actor")
        parts.append(node.name.text)
        if let genericParams = node.genericParameterClause {
            parts.append(genericParams.trimmedDescription)
        }
        if let inheritanceClause = node.inheritanceClause {
            parts.append(inheritanceClause.trimmedDescription)
        }
        return parts.joined(separator: " ")
    }

    private func buildMacroSignature(_ node: MacroDeclSyntax) -> String {
        var parts: [String] = []
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }
        parts.append("macro")
        parts.append(node.name.text)
        if let genericParams = node.genericParameterClause {
            parts.append(genericParams.trimmedDescription)
        }
        parts.append(node.signature.parameterClause.trimmedDescription)
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
        for modifier in node.modifiers {
            parts.append(modifier.trimmedDescription)
        }
        parts.append(node.bindingSpecifier.text)
        parts.append(binding.pattern.trimmedDescription)
        if let typeAnnotation = binding.typeAnnotation {
            parts.append(typeAnnotation.trimmedDescription)
        }
        return parts.joined(separator: " ")
    }
}
