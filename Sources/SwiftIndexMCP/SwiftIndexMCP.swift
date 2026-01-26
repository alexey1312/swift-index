// MARK: - SwiftIndexMCP

import Foundation
import SwiftIndexCore

/// SwiftIndex MCP Server
///
/// Provides MCP (Model Context Protocol) tools for AI assistants:
/// - `index_codebase` - Index a Swift project
/// - `search_code` - Hybrid semantic search
/// - `search_docs` - Search documentation
/// - `code_research` - Multi-hop architectural analysis
///
/// ## Usage
///
/// ### As MCP Server
///
/// Run the server in MCP mode to accept JSON-RPC requests over stdin/stdout:
///
/// ```bash
/// swiftindex serve
/// ```
///
/// ### Programmatic Usage
///
/// ```swift
/// import SwiftIndexMCP
///
/// // Create and run MCP server
/// let server = MCPServer()
/// await server.run()
///
/// // Or register custom tools
/// await server.registerTool(MyCustomTool())
/// ```
///
/// ## MCP Protocol
///
/// The server implements MCP (Model Context Protocol) specification:
/// - JSON-RPC 2.0 over stdin/stdout
/// - Initialize/initialized handshake
/// - tools/list and tools/call methods
///
/// ## Available Tools
///
/// ### index_codebase
///
/// Index a Swift codebase for semantic search.
///
/// ```json
/// {
///   "name": "index_codebase",
///   "arguments": {
///     "path": "/path/to/project",
///     "force": false
///   }
/// }
/// ```
///
/// ### search_code
///
/// Search indexed code using hybrid semantic search.
///
/// ```json
/// {
///   "name": "search_code",
///   "arguments": {
///     "query": "authentication flow",
///     "limit": 10
///   }
/// }
/// ```
///
/// ### code_research
///
/// Perform multi-hop code research and analysis.
///
/// ```json
/// {
///   "name": "code_research",
///   "arguments": {
///     "query": "how does the search engine work",
///     "depth": 2
///   }
/// }
/// ```

// MARK: - Re-exports

// Protocol types
@_exported import struct Foundation.Date
@_exported import struct Foundation.URL
