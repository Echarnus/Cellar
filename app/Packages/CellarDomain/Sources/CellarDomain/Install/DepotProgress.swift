import Foundation

/// Reads DepotDownloader's per-file progress lines — ` 12.34% game\data\file.pak` — for how much of
/// the depot is down. The number is the whole depot's, not the file's, which is what makes it a bar.
public enum DepotProgress {
    public static func fraction(in line: String) -> Double? {
        let trimmed = line.drop { $0 == " " }
        guard let percent = trimmed.firstIndex(of: "%") else { return nil }
        let number = trimmed[trimmed.startIndex..<percent]
        // The tool formats with the machine's locale, so a Belgian Mac writes "12,34%".
        guard !number.isEmpty, number.count <= 6,
              number.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }),
              let value = Double(number.replacingOccurrences(of: ",", with: ".")),
              (0...100).contains(value) else { return nil }
        let after = trimmed[trimmed.index(after: percent)...]
        guard after.isEmpty || after.first == " " else { return nil }
        return value / 100
    }
}
