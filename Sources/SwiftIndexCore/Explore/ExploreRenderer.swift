// MARK: - ExploreRenderer

import Foundation

/// Turns an explore plan into Read-compatible text within a character budget.
///
/// Source lines use the `<line>\t<text>` shape of an editor Read tool, so an agent
/// can edit from the answer without a second read.
public struct ExploreRenderer: Sendable {
    /// Bodies longer than this show a window around the relevant call site.
    static let longBodyLines = 60
    static let windowRadius = 15
    static let maxLineLength = 300

    private let readFile: @Sendable (String) -> String?

    public init(readFile: @escaping @Sendable (String) -> String? = ExploreRenderer.readFromDisk) {
        self.readFile = readFile
    }

    public static func readFromDisk(_ path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }

    public func render(_ plan: ExplorePlan, options: ExploreOptions) -> String {
        let header = "explore \"\(plan.query)\": \(plan.files.count) file(s)"
        let footer = footerLines(plan).joined(separator: "\n")
        guard !plan.files.isEmpty else {
            return header + "\nNo matching code. Try other words, or search_code for a text search."
        }

        var remaining = plan.budget.characters - header.count - footer.count - 16
        var remainingWeight = plan.files.reduce(0) { $0 + weight(of: $1) }
        var sections: [String] = []
        for file in plan.files {
            let share = remainingWeight > 0 ? weight(of: file) / remainingWeight : 1
            let allowance = max(Int(Double(remaining) * share), 0)
            let section = renderFile(file, plan: plan, allowance: allowance, options: options)
            sections.append(section)
            remaining -= section.count + 2
            remainingWeight -= weight(of: file)
        }

        return ([header] + sections + (footer.isEmpty ? [] : [footer])).joined(separator: "\n\n")
    }

    // MARK: - Files

    private func weight(of file: ExploreFile) -> Double {
        file.score * (file.onSpine ? 2 : 1)
    }

    private func renderFile(
        _ file: ExploreFile,
        plan: ExplorePlan,
        allowance: Int,
        options: ExploreOptions
    ) -> String {
        let title = "## " + relative(file.path, root: options.projectRoot)
        guard let content = readFile(file.path) else {
            return title + "\n(file is not readable; it may have been deleted since indexing)"
        }
        let lines = content.components(separatedBy: "\n")

        var banner = ""
        let changed = file.declarations.first.map { $0.fileHash != FileHasher.hash(content) } ?? false
        if options.dirtyPaths.contains(file.path) || changed {
            banner = "\n(changed since indexing: symbol line numbers may be off; Read before editing)"
        }

        var regions = file.symbols.map { lineNumbers(for: $0.symbol, in: file, plan: plan, lineCount: lines.count) }
        regions += file.chunkRanges.map { Array($0.clamped(to: 1 ... max(lines.count, 1))) }

        let selected = select(regions, lines: lines, allowance: allowance - title.count - banner.count)
        return title + banner + "\n" + format(selected, lines: lines)
    }

    /// Adds regions in priority order while they fit. The first region always
    /// appears, cut to fit, so a selected file never renders empty.
    private func select(_ regions: [[Int]], lines: [String], allowance: Int) -> [Int] {
        var selected = Set<Int>()
        var used = 0
        for region in regions {
            let added = region.filter { !selected.contains($0) }
            let cost = added.reduce(0) { $0 + lineCost($1, lines: lines) }
            if used + cost <= allowance {
                selected.formUnion(added)
                used += cost
            } else if selected.isEmpty {
                for line in added {
                    let lineCost = lineCost(line, lines: lines)
                    guard used + lineCost <= allowance else { break }
                    selected.insert(line)
                    used += lineCost
                }
            }
        }
        return selected.sorted()
    }

    private func lineNumbers(for symbol: SymbolNode, in file: ExploreFile, plan: ExplorePlan, lineCount: Int) -> [Int] {
        let start = min(max(symbol.startLine, 1), max(lineCount, 1))
        let end = min(max(symbol.endLine, start), max(lineCount, 1))
        let span = end - start + 1

        if symbol.kind == .type || symbol.kind == .protocolDecl, !file.onSpine || span > Self.longBodyLines {
            let members = file.declarations
                .filter { $0.container == symbol.name && $0.startLine > start && $0.startLine <= end }
                .map(\.startLine)
            return [start] + members + [end]
        }

        guard span > Self.longBodyLines else {
            return Array(start ... end)
        }
        if let site = plan.callSites[symbol.id]?.first(where: { $0 >= start && $0 <= end }) {
            let window = max(start, site - Self.windowRadius) ... min(end, site + Self.windowRadius)
            return [start] + Array(window)
        }
        return Array(start ... min(end, start + 2 * Self.windowRadius))
    }

    private func lineCost(_ number: Int, lines: [String]) -> Int {
        min(lines[number - 1].count, Self.maxLineLength) + String(number).count + 2
    }

    private func format(_ numbers: [Int], lines: [String]) -> String {
        var output: [String] = []
        var previous: Int?
        for number in numbers {
            if let previous, number > previous + 1 {
                output.append("⋮")
            }
            var text = lines[number - 1]
            if text.count > Self.maxLineLength {
                text = String(text.prefix(Self.maxLineLength)) + "…"
            }
            output.append("\(number)\t\(text)")
            previous = number
        }
        return output.joined(separator: "\n")
    }

    // MARK: - Footer

    private func footerLines(_ plan: ExplorePlan) -> [String] {
        var lines: [String] = []
        if plan.spine.count > 1 {
            lines.append("call path: " + plan.spine.joined(separator: " → "))
        }
        if let impact = plan.impact, impact.symbols > 0 {
            lines.append(
                "blast radius of \(impact.symbolName): \(impact.symbols) symbols in \(impact.files) files, "
                    + "\(impact.tests) test files"
            )
        }
        return lines
    }

    private func relative(_ path: String, root: String?) -> String {
        guard let root else { return path }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
}
