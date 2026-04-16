import Foundation

extension Character {
    var isHangulSyllable: Bool {
        unicodeScalars.allSatisfy { (0xAC00...0xD7A3).contains(Int($0.value)) }
    }

    var isHangulCompatibilityJamo: Bool {
        unicodeScalars.allSatisfy { (0x3131...0x318E).contains(Int($0.value)) }
    }
}