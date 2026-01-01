import Foundation

final class DictionaryService {
    static let shared = DictionaryService()
    private init() {}

    private var dict: [String: String] = [:]
    private var loaded = false

    func definition(for hanzi: String) -> String? {
        ensureLoaded()
        return dict[hanzi]
    }

    private func ensureLoaded() {
        if loaded { return }
        loaded = true
        // Attempt to load the CSV from bundle
        // Ensure the file is added to the app target resources
        let name = "Chinese Language Dictionary - All Characters (Frequency)"
        print("DictionaryService: Looking for CSV...")
        if let url = Bundle.main.url(forResource: name, withExtension: "csv") {
            print("DictionaryService: Found at \(url)")
            loadCSV(from: url)
        } else {
            print("DictionaryService: ❌ CSV FILE NOT FOUND IN BUNDLE!")
            print("DictionaryService: Make sure the CSV is added to the app target")
        }
    }

    private func loadCSV(from url: URL) {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            return
        }
        var lines = text.split(whereSeparator: { $0.isNewline }).map(String.init)
        if lines.isEmpty { return }
        // If header detected, skip first line (heuristic: contains ASCII letters)
        if lines[0].range(of: "[A-Za-z]", options: .regularExpression) != nil {
            lines.removeFirst()
        }
        for line in lines {
            let cols = parseCSVRow(line)
            if cols.count < 4 { continue }
            // CSV format: hanzi, pinyin, tone, definition
            let hanzi = cols[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let def = cols[3].trimmingCharacters(in: .whitespacesAndNewlines)
            if hanzi.isEmpty || def.isEmpty { continue }
            if dict[hanzi] == nil { 
                dict[hanzi] = def
                // Debug first few entries
                if dict.count <= 5 {
                    print("Loaded: '\(hanzi)' -> '\(def)'")
                }
            }
        }
        print("DictionaryService: Total loaded = \(dict.count) definitions")
    }

    private func extractFirstHanzi(from text: String) -> String {
        for s in text.unicodeScalars {
            let v = s.value
            if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v) {
                return String(s)
            }
        }
        return ""
    }

    private func parseCSVRow(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        var prev: Swift.Character? = nil
        while let ch = iterator.next() {
            if ch == "\"" {
                if inQuotes {
                    // lookahead for escaped quote
                    if let next = iterator.next() {
                        if next == "\"" {
                            current.append("\"")
                        } else if next == "," {
                            inQuotes = false
                            result.append(current)
                            current.removeAll(keepingCapacity: true)
                        } else {
                            inQuotes = false
                            current.append(next)
                        }
                        prev = next
                        continue
                    } else {
                        inQuotes = false
                    }
                } else if prev == nil || prev == "," {
                    inQuotes = true
                } else {
                    current.append(ch)
                }
            } else if ch == "," && !inQuotes {
                result.append(current)
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(ch)
            }
            prev = ch
        }
        result.append(current)
        return result
    }
}
