// Sample Swift file for testing

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
        "Hello, my name is \(name)"
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
        "\(name), age \(age)"
    }
}

/// A free function for testing.
func calculateSum(_ numbers: [Int]) -> Int {
    numbers.reduce(0, +)
}
