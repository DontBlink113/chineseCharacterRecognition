import Foundation
import CoreGraphics

// MARK: - Validation Entry Models

/// A single validation entry containing user-drawn strokes and ground truth labels
struct ValidationEntry: Codable, Identifiable {
    let id: UUID
    let character: String
    let timestamp: Date
    let userStrokes: [LabeledStroke]
    let referenceStrokeCount: Int
    
    init(id: UUID = UUID(), character: String, timestamp: Date = Date(), userStrokes: [LabeledStroke], referenceStrokeCount: Int) {
        self.id = id
        self.character = character
        self.timestamp = timestamp
        self.userStrokes = userStrokes
        self.referenceStrokeCount = referenceStrokeCount
    }
}

/// A user-drawn stroke with its ground truth label
struct LabeledStroke: Codable, Identifiable {
    let id: UUID
    let strokeIndex: Int
    let points: [[Double]] // Raw coordinates [x, y]
    let groundTruthMatch: Int? // nil = extra stroke, otherwise index of reference stroke
    let missingSubstrokes: [Int] // Array of missing substroke indices (1, 2, 3, 4)
    
    init(id: UUID = UUID(), strokeIndex: Int, points: [[Double]], groundTruthMatch: Int?, missingSubstrokes: [Int] = []) {
        self.id = id
        self.strokeIndex = strokeIndex
        self.points = points
        self.groundTruthMatch = groundTruthMatch
        self.missingSubstrokes = missingSubstrokes
    }
    
    /// Create from a Stroke object
    static func from(stroke: Stroke, strokeIndex: Int, groundTruthMatch: Int?, missingSubstrokes: [Int] = []) -> LabeledStroke {
        let points = stroke.points.map { point in
            [Double(point.location.x), Double(point.location.y)]
        }
        return LabeledStroke(strokeIndex: strokeIndex, points: points, groundTruthMatch: groundTruthMatch, missingSubstrokes: missingSubstrokes)
    }
}

// MARK: - Validation Dataset Manager

class ValidationDatasetManager {
    static let shared = ValidationDatasetManager()
    
    private let fileName = "validation_dataset.jsonl"
    
    private var fileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(fileName)
    }
    
    private init() {
        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }
    
    /// Save a validation entry to the dataset
    func saveEntry(_ entry: ValidationEntry) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let jsonData = try encoder.encode(entry)
        guard var jsonString = String(data: jsonData, encoding: .utf8) else {
            throw ValidationError.encodingFailed
        }
        
        // Add newline
        jsonString += "\n"
        
        // Append to file
        if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
            fileHandle.seekToEndOfFile()
            if let data = jsonString.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        } else {
            // File doesn't exist, create it
            try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
    
    /// Load all validation entries from the dataset
    func loadEntries() throws -> [ValidationEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        var entries: [ValidationEntry] = []
        for line in lines {
            if let data = line.data(using: .utf8) {
                do {
                    let entry = try decoder.decode(ValidationEntry.self, from: data)
                    entries.append(entry)
                } catch {
                    print("Failed to decode entry: \(error)")
                    // Continue with other entries
                }
            }
        }
        
        return entries
    }
    
    /// Delete a specific entry
    func deleteEntry(_ entryId: UUID) throws {
        var entries = try loadEntries()
        entries.removeAll { $0.id == entryId }
        
        // Rewrite entire file
        try rewriteFile(with: entries)
    }
    
    /// Clear all entries
    func clearAll() throws {
        try "".write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    /// Get the file URL for sharing/export
    func getFileURL() -> URL {
        return fileURL
    }
    
    /// Rewrite the entire file with given entries
    private func rewriteFile(with entries: [ValidationEntry]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        var content = ""
        for entry in entries {
            let jsonData = try encoder.encode(entry)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                content += jsonString + "\n"
            }
        }
        
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

// MARK: - Errors

enum ValidationError: Error, LocalizedError {
    case encodingFailed
    case decodingFailed
    case fileNotFound
    
    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode validation entry"
        case .decodingFailed:
            return "Failed to decode validation entry"
        case .fileNotFound:
            return "Validation dataset file not found"
        }
    }
}
