import Foundation
import TOML

extension TOMLValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
            return
        }

        if let value = try? container.decode(Int64.self) {
            self = .integer(value)
            return
        }

        if let value = try? container.decode(Double.self) {
            self = .float(value)
            return
        }

        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }

        if let value = try? container.decode(LocalDateTime.self) {
            self = .localDateTime(value)
            return
        }

        if let value = try? container.decode(LocalDate.self) {
            self = .localDate(value)
            return
        }

        if let value = try? container.decode(LocalTime.self) {
            self = .localTime(value)
            return
        }

        if let value = try? container.decode(Date.self) {
            self = .offsetDateTime(value)
            return
        }

        if let value = try? container.decode([TOMLValue].self) {
            self = .array(value)
            return
        }

        if let value = try? container.decode([String: TOMLValue].self) {
            self = .table(value)
            return
        }

        throw DecodingError.typeMismatch(
            TOMLValue.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported TOML value"
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .float(value):
            try container.encode(value)
        case let .boolean(value):
            try container.encode(value)
        case let .offsetDateTime(value):
            try container.encode(value)
        case let .localDateTime(value):
            try container.encode(value)
        case let .localDate(value):
            try container.encode(value)
        case let .localTime(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .table(value):
            try container.encode(value)
        }
    }
}
