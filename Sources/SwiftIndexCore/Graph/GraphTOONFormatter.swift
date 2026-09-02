// MARK: - GraphTOONFormatter

import Foundation

/// Renders graph results compactly.
///
/// Paths and qualified names dominate graph output and repeat constantly, so symbols
/// are interned once into a table and referenced by index everywhere else. Provenance
/// is always shown: a heuristic hop must never read as fact.
public enum GraphTOONFormatter {
    public static func format(_ result: GraphNeighborhood, includeSource: Bool = false) -> String {
        var indexByID: [String: Int] = [result.root.id: 0]
        var ordered: [SymbolNode] = [result.root]

        for node in result.nodes where indexByID[node.symbol.id] == nil {
            indexByID[node.symbol.id] = ordered.count
            ordered.append(node.symbol)
        }

        var output = "graph{sym,rel,depth,n,resolved,unresolved,truncated}:\n"
        output += "  \"\(result.root.qualifiedName)\",\"\(result.relation.rawValue)\","
        output += "\(result.depth),\(result.nodes.count),"
        output += "\(result.edges.count - result.unresolvedCount),\(result.unresolvedCount),"
        output += "\(result.truncated ? 1 : 0)\n\n"

        output += "syms[\(ordered.count)]{i,q,k,p,l,deg}:\n"
        for (index, symbol) in ordered.enumerated() {
            output += "  \(index),\"\(symbol.qualifiedName)\",\(symbol.kind.rawValue),"
            output += "\"\(symbol.path)\",\(symbol.startLine),\(symbol.inDegree)\n"
        }

        let renderable = result.edges.filter { edge in
            guard let targetID = edge.targetID else { return false }
            return indexByID[edge.sourceID] != nil && indexByID[targetID] != nil
        }

        if !renderable.isEmpty {
            output += "\nedges[\(renderable.count)]{s,d,k,c,pv,n}:\n"
            for edge in renderable {
                guard let source = indexByID[edge.sourceID],
                      let targetID = edge.targetID,
                      let target = indexByID[targetID]
                else {
                    continue
                }
                let confidence = String(format: "%.2f", edge.confidence)
                output += "  \(source),\(target),\(edge.kind.rawValue),\(confidence),"
                output += "\(abbreviate(edge.provenance)),\(edge.occurrences)\n"
            }
        }

        if !result.paths.isEmpty {
            output += "\npaths[\(result.paths.count)]:\n"
            for path in result.paths {
                let chain = path.symbolIDs.compactMap { indexByID[$0].map(String.init) }
                output += "  \(chain.joined(separator: ">"))\n"
            }
        }

        output += "\nimpact{files,modules,public_api,frontier_unresolved}:\n"
        output += "  \(result.fileCount),\(result.moduleCount),"
        output += "\(result.publicAPICount),\(result.unresolvedCount)\n"

        // Name the rule behind every guess, so the reader can weigh it.
        let notes = renderable
            .filter { $0.provenance == .heuristic && $0.synthesizedBy != nil }
            .compactMap { edge -> String? in
                guard let source = indexByID[edge.sourceID],
                      let targetID = edge.targetID,
                      let target = indexByID[targetID],
                      let rule = edge.synthesizedBy
                else {
                    return nil
                }
                return "  \"\(source)>\(target) \(rule), confidence \(String(format: "%.2f", edge.confidence))\""
            }

        if !notes.isEmpty {
            output += "\nnotes[\(notes.count)]:\n"
            output += notes.joined(separator: "\n") + "\n"
        }

        return output
    }

    /// Human-readable rendering.
    public static func formatHuman(_ result: GraphNeighborhood) -> String {
        var lines: [String] = []
        lines.append("\(result.relation.rawValue) of \(result.root.qualifiedName) (depth \(result.depth))")
        lines.append("")

        if result.nodes.isEmpty {
            lines.append("  none found")
        } else {
            for node in result.nodes {
                let location = "\(node.symbol.path):\(node.symbol.startLine)"
                lines.append("  [\(node.depth)] \(node.symbol.qualifiedName)  \(location)")
            }
        }

        if !result.paths.isEmpty {
            lines.append("")
            lines.append("Paths:")
            for path in result.paths {
                let confidence = String(format: "%.2f", path.confidence)
                lines.append("  \(path.symbolIDs.count) hops (confidence \(confidence))")
            }
        }

        lines.append("")
        lines.append("Impact: \(result.fileCount) files, \(result.moduleCount) modules, "
            + "\(result.publicAPICount) public symbols")

        if result.unresolvedCount > 0 {
            lines.append("Unresolved frontier: \(result.unresolvedCount) edge(s) — traversal is incomplete")
        }
        if result.truncated {
            lines.append("Truncated: node budget reached")
        }

        return lines.joined(separator: "\n")
    }

    private static func abbreviate(_ provenance: EdgeProvenance) -> String {
        switch provenance {
        case .syntactic: "syn"
        case .heuristic: "heu"
        case .indexstore: "ist"
        }
    }
}
