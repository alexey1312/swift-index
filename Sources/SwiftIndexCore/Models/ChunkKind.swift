// MARK: - ChunkKind Enum

import Foundation

/// The type of code construct a chunk represents.
public enum ChunkKind: String, Sendable, Equatable, Codable, CaseIterable {
    // MARK: - Swift Types

    case function
    case method
    case initializer
    case deinitializer
    case `subscript`
    case `class`
    case `struct`
    case `enum`
    case `protocol`
    case `extension`
    case actor
    case macro
    case `typealias`
    case variable
    case constant

    // MARK: - Objective-C Types

    case objcInterface
    case objcImplementation
    case objcMethod
    case objcProperty
    case objcCategory

    // MARK: - C Types

    case cFunction
    case cStruct
    case cTypedef
    case cMacro

    // MARK: - Data Types

    case jsonObject
    case jsonArray
    case yamlMapping
    case yamlSequence

    // MARK: - Documentation

    case markdownSection
    case markdownCodeBlock
    case comment
    case section
    case document

    // MARK: - C++ Types

    case namespace

    // MARK: - Generic

    case file
    case interface
    case unknown
}

// MARK: - Convenience Properties

public extension ChunkKind {
    /// Whether this is a Swift-specific chunk kind.
    var isSwift: Bool {
        switch self {
        case .function, .method, .initializer, .deinitializer, .subscript,
             .class, .struct, .enum, .protocol, .extension, .actor,
             .macro, .typealias, .variable, .constant:
            true
        default:
            false
        }
    }

    /// Whether this is an Objective-C chunk kind.
    var isObjC: Bool {
        switch self {
        case .objcInterface, .objcImplementation, .objcMethod,
             .objcProperty, .objcCategory:
            true
        default:
            false
        }
    }

    /// Whether this is a C chunk kind.
    var isC: Bool {
        switch self {
        case .cFunction, .cStruct, .cTypedef, .cMacro:
            true
        default:
            false
        }
    }

    /// Whether this represents a type declaration.
    var isTypeDeclaration: Bool {
        switch self {
        case .class, .struct, .enum, .protocol, .actor,
             .objcInterface, .cStruct:
            true
        default:
            false
        }
    }

    /// Whether this represents a callable.
    var isCallable: Bool {
        switch self {
        case .function, .method, .initializer, .subscript,
             .objcMethod, .cFunction:
            true
        default:
            false
        }
    }
}
