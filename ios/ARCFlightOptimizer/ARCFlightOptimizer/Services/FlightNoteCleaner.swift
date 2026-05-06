import Foundation

enum FlightNoteCleaner {
    static func editableNotes(from notes: String) -> String {
        var keptLines: [String] = []
        for line in notes.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                if !keptLines.isEmpty {
                    keptLines.append("")
                }
                continue
            }
            if trimmed.lowercased() == "imported" {
                break
            }
            if isImportMetadataLine(trimmed) {
                break
            }
            keptLines.append(line)
        }
        return keptLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isImportMetadataLine(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        let metadataPrefixes = [
            "imported ",
            "import checked",
            "import review:",
            "import warning:",
                "sheet pattern check:",
                "weather conditions:",
                "recovery blanket/wadding:",
                "column map:",
                "matched:",
                "<td",
                "</"
            ]
            return metadataPrefixes.contains { lowercased.hasPrefix($0) }
        }
    }
