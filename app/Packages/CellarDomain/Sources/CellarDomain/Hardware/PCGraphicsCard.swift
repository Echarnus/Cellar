import Foundation

/// A Windows PC graphics card, as a publisher names it in a game's system requirements.
///
/// Scores are on the same scale as `MacChip.Specs.gpuScore` (the M1's 8-core GPU = 100), from
/// public benchmarks: Notebookcheck measures the M1 at about half a desktop GTX 1660, and the
/// cards are placed against each other by their relative performance in the same comparisons.
/// They are approximate on purpose — a requirement is a bracket, not a frame-rate promise — and a
/// card that isn't here makes `MacRequirementsTests` fail, so a new profile adds its card rather
/// than guessing a chip. See `docs/MAC-REQUIREMENTS.md`.
public struct PCGraphicsCard: Sendable, Equatable {
    public let name: String
    public let score: Int
    /// Its video memory, in GB — which a Mac takes out of the same unified memory as the game.
    public let videoMemoryGB: Double

    public init(_ name: String, score: Int, videoMemoryGB: Double) {
        self.name = name
        self.score = score
        self.videoMemoryGB = videoMemoryGB
    }

    /// The card a profile names, matched without regard to case, spacing or the maker's name in
    /// front ("NVIDIA GeForce GTX 1060" and "GTX 1060" are the same card).
    public static func named(_ text: String) -> PCGraphicsCard? {
        let key = normalized(text)
        return all.first { normalized($0.name) == key }
    }

    static func normalized(_ text: String) -> String {
        var words = text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ").map(String.init)
        while let first = words.first, ["nvidia", "amd", "ati", "intel", "geforce", "radeon"].contains(first) {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }

    /// The cards the shipped profiles name, and their neighbours. Generic entries stand for the
    /// requirements old games state as a class of card ("a DirectX 8 card with 32 MB").
    public static let all: [PCGraphicsCard] = [
        // Generic classes, for games older than any card a publisher still names.
        PCGraphicsCard("DirectX 8 card", score: 1, videoMemoryGB: 0.0625),
        PCGraphicsCard("DirectX 9 card with Shader Model 3", score: 5, videoMemoryGB: 0.25),
        PCGraphicsCard("DirectX 11 card with 1 GB", score: 45, videoMemoryGB: 1),
        // Integrated.
        PCGraphicsCard("Intel HD Graphics 2500", score: 6, videoMemoryGB: 0.5),
        PCGraphicsCard("Intel HD Graphics 4000", score: 10, videoMemoryGB: 0.5),
        // NVIDIA, oldest first.
        PCGraphicsCard("GeForce 6600 GT", score: 3, videoMemoryGB: 0.125),
        PCGraphicsCard("GeForce 6800", score: 5, videoMemoryGB: 0.25),
        PCGraphicsCard("GeForce 7900 GT", score: 9, videoMemoryGB: 0.25),
        PCGraphicsCard("GeForce 8600 GT", score: 8, videoMemoryGB: 0.5),
        PCGraphicsCard("GeForce 8800 GT", score: 20, videoMemoryGB: 0.5),
        PCGraphicsCard("GeForce 9800 GT", score: 22, videoMemoryGB: 1),
        PCGraphicsCard("GeForce GTS 250", score: 25, videoMemoryGB: 1),
        PCGraphicsCard("GeForce GTX 260", score: 30, videoMemoryGB: 0.875),
        PCGraphicsCard("GeForce GTX 460", score: 45, videoMemoryGB: 1),
        PCGraphicsCard("GeForce GTX 465", score: 45, videoMemoryGB: 1),
        PCGraphicsCard("GeForce GTX 470", score: 55, videoMemoryGB: 1.25),
        PCGraphicsCard("GeForce GTX 550 Ti", score: 40, videoMemoryGB: 1),
        PCGraphicsCard("GeForce GTX 560", score: 55, videoMemoryGB: 1),
        PCGraphicsCard("GeForce GTX 650", score: 45, videoMemoryGB: 1),
        PCGraphicsCard("GeForce GTX 650 Ti", score: 55, videoMemoryGB: 1),
        PCGraphicsCard("GeForce GTX 660", score: 85, videoMemoryGB: 2),
        PCGraphicsCard("GeForce GTX 750", score: 60, videoMemoryGB: 1),
        PCGraphicsCard("GeForce GTX 750 Ti", score: 70, videoMemoryGB: 2),
        PCGraphicsCard("GeForce GTX 760", score: 95, videoMemoryGB: 2),
        PCGraphicsCard("GeForce GTX 770", score: 120, videoMemoryGB: 2),
        PCGraphicsCard("GeForce GTX 780", score: 140, videoMemoryGB: 3),
        PCGraphicsCard("GeForce GTX 950", score: 95, videoMemoryGB: 2),
        PCGraphicsCard("GeForce GTX 960", score: 115, videoMemoryGB: 4),
        PCGraphicsCard("GeForce GTX 970", score: 170, videoMemoryGB: 4),
        PCGraphicsCard("GeForce GTX 980", score: 210, videoMemoryGB: 4),
        PCGraphicsCard("GeForce GTX 1050", score: 90, videoMemoryGB: 2),
        PCGraphicsCard("GeForce GTX 1050 Ti", score: 120, videoMemoryGB: 4),
        PCGraphicsCard("GeForce GTX 1060 3GB", score: 165, videoMemoryGB: 3),
        PCGraphicsCard("GeForce GTX 1060", score: 180, videoMemoryGB: 6),
        PCGraphicsCard("GeForce GTX 1070", score: 250, videoMemoryGB: 8),
        PCGraphicsCard("GeForce GTX 1070 Ti", score: 270, videoMemoryGB: 8),
        PCGraphicsCard("GeForce GTX 1080", score: 300, videoMemoryGB: 8),
        PCGraphicsCard("GeForce GTX 1080 Ti", score: 400, videoMemoryGB: 11),
        PCGraphicsCard("GeForce GTX 1630", score: 85, videoMemoryGB: 4),
        PCGraphicsCard("GeForce GTX 1650", score: 140, videoMemoryGB: 4),
        PCGraphicsCard("GeForce GTX 1660", score: 200, videoMemoryGB: 6),
        PCGraphicsCard("GeForce GTX 1660 Super", score: 230, videoMemoryGB: 6),
        PCGraphicsCard("GeForce GTX 1660 Ti", score: 235, videoMemoryGB: 6),
        PCGraphicsCard("GeForce RTX 2060", score: 280, videoMemoryGB: 6),
        PCGraphicsCard("GeForce RTX 2060 Super", score: 320, videoMemoryGB: 8),
        PCGraphicsCard("GeForce RTX 2070", score: 330, videoMemoryGB: 8),
        PCGraphicsCard("GeForce RTX 2070 Super", score: 370, videoMemoryGB: 8),
        PCGraphicsCard("GeForce RTX 2080", score: 390, videoMemoryGB: 8),
        PCGraphicsCard("GeForce RTX 2080 Ti", score: 500, videoMemoryGB: 11),
        PCGraphicsCard("GeForce RTX 3060", score: 340, videoMemoryGB: 12),
        PCGraphicsCard("GeForce RTX 3060 Ti", score: 440, videoMemoryGB: 8),
        PCGraphicsCard("GeForce RTX 3070", score: 500, videoMemoryGB: 8),
        PCGraphicsCard("GeForce RTX 3080", score: 650, videoMemoryGB: 10),
        PCGraphicsCard("GeForce RTX 4060", score: 380, videoMemoryGB: 8),
        PCGraphicsCard("GeForce RTX 4070", score: 600, videoMemoryGB: 12),
        // AMD.
        PCGraphicsCard("Radeon HD 3870", score: 20, videoMemoryGB: 0.5),
        PCGraphicsCard("Radeon HD 6450", score: 8, videoMemoryGB: 0.5),
        PCGraphicsCard("Radeon HD 6870", score: 50, videoMemoryGB: 1),
        PCGraphicsCard("Radeon HD 7750", score: 50, videoMemoryGB: 1),
        PCGraphicsCard("Radeon HD 7770", score: 60, videoMemoryGB: 1),
        PCGraphicsCard("Radeon HD 7850", score: 95, videoMemoryGB: 2),
        PCGraphicsCard("Radeon HD 7870", score: 110, videoMemoryGB: 2),
        PCGraphicsCard("Radeon R7 360", score: 75, videoMemoryGB: 2),
        PCGraphicsCard("Radeon R9 290", score: 160, videoMemoryGB: 4),
        PCGraphicsCard("Radeon R9 290X", score: 175, videoMemoryGB: 4),
        PCGraphicsCard("Radeon RX 460", score: 70, videoMemoryGB: 2),
        PCGraphicsCard("Radeon RX 470", score: 150, videoMemoryGB: 4),
        PCGraphicsCard("Radeon RX 480", score: 170, videoMemoryGB: 8),
        PCGraphicsCard("Radeon RX 570", score: 155, videoMemoryGB: 4),
        PCGraphicsCard("Radeon RX 580", score: 175, videoMemoryGB: 8),
        PCGraphicsCard("Radeon RX 5500 XT", score: 175, videoMemoryGB: 8),
        PCGraphicsCard("Radeon RX 5600 XT", score: 260, videoMemoryGB: 6),
        PCGraphicsCard("Radeon RX 5700", score: 290, videoMemoryGB: 8),
        PCGraphicsCard("Radeon RX 5700 XT", score: 330, videoMemoryGB: 8),
        PCGraphicsCard("Radeon RX 6400", score: 75, videoMemoryGB: 4),
        PCGraphicsCard("Radeon RX 6700", score: 400, videoMemoryGB: 10),
        PCGraphicsCard("Radeon RX 6700 XT", score: 440, videoMemoryGB: 12),
        // Intel Arc.
        PCGraphicsCard("Intel Arc A380", score: 120, videoMemoryGB: 6),
        PCGraphicsCard("Intel Arc A750", score: 320, videoMemoryGB: 8),
        PCGraphicsCard("Intel Arc A770", score: 360, videoMemoryGB: 16),
    ]
}
