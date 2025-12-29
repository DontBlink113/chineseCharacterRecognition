import Foundation
import SwiftUI

// MARK: - Validation Result Models

/// Result of validating a single entry
struct ValidationResult: Identifiable {
    let id = UUID()
    let entry: ValidationEntry
    let predictions: [Int?] // Predicted match for each stroke (nil = no match)
    let groundTruth: [Int?] // Ground truth match for each stroke
    let isCorrect: Bool // True if all predictions match ground truth
    let accuracy: Double // Percentage of correct stroke matches
    
    /// Number of correctly matched strokes
    var correctCount: Int {
        zip(predictions, groundTruth).filter { $0 == $1 }.count
    }
    
    /// Number of incorrectly matched strokes
    var incorrectCount: Int {
        predictions.count - correctCount
    }
    
    /// Detailed comparison for each stroke
    var strokeComparisons: [(strokeIndex: Int, predicted: Int?, actual: Int?, isCorrect: Bool)] {
        zip(predictions, groundTruth).enumerated().map { index, pair in
            (strokeIndex: index, predicted: pair.0, actual: pair.1, isCorrect: pair.0 == pair.1)
        }
    }
}

/// Overall validation metrics across all entries
struct ValidationMetrics {
    let totalEntries: Int
    let totalStrokes: Int
    let correctStrokes: Int
    let incorrectStrokes: Int
    let perfectEntries: Int // Entries where all strokes are correct
    
    var overallAccuracy: Double {
        guard totalStrokes > 0 else { return 0 }
        return Double(correctStrokes) / Double(totalStrokes)
    }
    
    var perfectEntryRate: Double {
        guard totalEntries > 0 else { return 0 }
        return Double(perfectEntries) / Double(totalEntries)
    }
    
    /// Per-character breakdown
    var characterMetrics: [String: CharacterMetrics] = [:]
}

/// Metrics for a specific character
struct CharacterMetrics {
    let character: String
    let totalEntries: Int
    let totalStrokes: Int
    let correctStrokes: Int
    let perfectEntries: Int
    
    var accuracy: Double {
        guard totalStrokes > 0 else { return 0 }
        return Double(correctStrokes) / Double(totalStrokes)
    }
}

// MARK: - Stroke Matching Validator

class StrokeMatchingValidator: ObservableObject {
    @Published var isValidating = false
    @Published var progress: Double = 0
    @Published var results: [ValidationResult] = []
    @Published var metrics: ValidationMetrics?
    
    // Algorithm parameters (can be tuned)
    var errorThreshold: Double = 0.5
    var distanceWeight: Double = 0.7
    var lengthWeight: Double = 0.3
    var temperature: Double = 0.1
    var priorSigma: Double = 2.0
    
    // Cache graphics data to avoid reloading for every entry
    private var graphicsDataCache: [String: ReferenceCharacter]?
    
    /// Run validation on all entries in the dataset
    func validateDataset() async {
        await MainActor.run {
            isValidating = true
            progress = 0
            results = []
            metrics = nil
        }
        
        // Load graphics data once and cache it
        if graphicsDataCache == nil {
            graphicsDataCache = StrokeAnalyzer.loadGraphicsData()
        }
        
        // Load all validation entries
        let entries: [ValidationEntry]
        do {
            entries = try ValidationDatasetManager.shared.loadEntries()
        } catch {
            print("Error loading validation entries: \(error)")
            await MainActor.run { isValidating = false }
            return
        }
        
        guard !entries.isEmpty else {
            await MainActor.run { isValidating = false }
            return
        }
        
        // Validate each entry
        var validationResults: [ValidationResult] = []
        
        for (index, entry) in entries.enumerated() {
            let result = validateEntry(entry)
            validationResults.append(result)
            
            // Update progress every 10 entries to reduce UI updates
            if index % 10 == 0 || index == entries.count - 1 {
                await MainActor.run {
                    progress = Double(index + 1) / Double(entries.count)
                }
            }
        }
        
        // Calculate overall metrics
        let calculatedMetrics = calculateMetrics(from: validationResults)
        
        await MainActor.run {
            results = validationResults
            metrics = calculatedMetrics
            isValidating = false
            progress = 1.0
        }
    }
    
    /// Validate a single entry (optimized with cached graphics data)
    func validateEntry(_ entry: ValidationEntry) -> ValidationResult {
        // Convert LabeledStrokes to regular Strokes for the analyzer
        let userStrokes = entry.userStrokes.map { labeledStroke -> Stroke in
            let baseTimestamp = Date().timeIntervalSince1970
            let strokePoints = labeledStroke.points.enumerated().map { index, pointArray in
                // pointArray is [Double] with [x, y]
                let x = pointArray.count > 0 ? CGFloat(pointArray[0]) : 0
                let y = pointArray.count > 1 ? CGFloat(pointArray[1]) : 0
                return StrokePoint(
                    location: CGPoint(x: x, y: y),
                    timestamp: baseTimestamp + TimeInterval(index) * 0.01
                )
            }
            return Stroke(id: labeledStroke.id, points: strokePoints)
        }
        
        // Use cached graphics data if available
        let graphicsData = graphicsDataCache ?? StrokeAnalyzer.loadGraphicsData()
        
        // Get reference character
        guard let refChar = graphicsData[entry.character] else {
            // Character not found, return all nil predictions
            let predictions: [Int?] = Array(repeating: nil, count: entry.userStrokes.count)
            let groundTruth = entry.userStrokes.map { $0.groundTruthMatch }
            return ValidationResult(
                entry: entry,
                predictions: predictions,
                groundTruth: groundTruth,
                isCorrect: false,
                accuracy: 0
            )
        }
        
        // Parse reference strokes
        let referenceStrokes = StrokeAnalyzer.normalizeReferenceStrokes(refChar.medians)
        
        guard !referenceStrokes.isEmpty else {
            let predictions: [Int?] = Array(repeating: nil, count: entry.userStrokes.count)
            let groundTruth = entry.userStrokes.map { $0.groundTruthMatch }
            return ValidationResult(
                entry: entry,
                predictions: predictions,
                groundTruth: groundTruth,
                isCorrect: false,
                accuracy: 0
            )
        }
        
        // Normalize user strokes
        let normalizedUserStrokes = StrokeAnalyzer.normalizeUserStrokes(userStrokes)
        
        // Analyze each user stroke
        var predictions: [Int?] = []
        
        for (userIdx, userStroke) in normalizedUserStrokes.enumerated() {
            // Calculate raw errors for all reference strokes
            var errors: [Double] = []
            for refStroke in referenceStrokes {
                let error = StrokeAnalyzer.calculateError(
                    userStroke: userStroke,
                    referenceStroke: refStroke,
                    distanceWeight: distanceWeight,
                    lengthWeight: lengthWeight
                )
                errors.append(error)
            }
            
            // Find best match based on raw error
            let bestMatchIndex = errors.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            let rawError = errors[bestMatchIndex]
            
            // Check if error exceeds threshold
            let isMatched = rawError <= errorThreshold
            predictions.append(isMatched ? bestMatchIndex : nil)
        }
        
        // Get ground truth
        let groundTruth = entry.userStrokes.map { $0.groundTruthMatch }
        
        // Calculate accuracy
        let correctCount = zip(predictions, groundTruth).filter { $0 == $1 }.count
        let accuracy = Double(correctCount) / Double(max(1, predictions.count))
        let isCorrect = correctCount == predictions.count
        
        return ValidationResult(
            entry: entry,
            predictions: predictions,
            groundTruth: groundTruth,
            isCorrect: isCorrect,
            accuracy: accuracy
        )
    }
    
    /// Calculate overall metrics from validation results
    private func calculateMetrics(from results: [ValidationResult]) -> ValidationMetrics {
        let totalEntries = results.count
        let totalStrokes = results.reduce(0) { $0 + $1.predictions.count }
        let correctStrokes = results.reduce(0) { $0 + $1.correctCount }
        let incorrectStrokes = totalStrokes - correctStrokes
        let perfectEntries = results.filter { $0.isCorrect }.count
        
        // Calculate per-character metrics
        var characterMetricsDict: [String: CharacterMetrics] = [:]
        
        let groupedByCharacter = Dictionary(grouping: results) { $0.entry.character }
        
        for (character, charResults) in groupedByCharacter {
            let charTotalEntries = charResults.count
            let charTotalStrokes = charResults.reduce(0) { $0 + $1.predictions.count }
            let charCorrectStrokes = charResults.reduce(0) { $0 + $1.correctCount }
            let charPerfectEntries = charResults.filter { $0.isCorrect }.count
            
            characterMetricsDict[character] = CharacterMetrics(
                character: character,
                totalEntries: charTotalEntries,
                totalStrokes: charTotalStrokes,
                correctStrokes: charCorrectStrokes,
                perfectEntries: charPerfectEntries
            )
        }
        
        var metrics = ValidationMetrics(
            totalEntries: totalEntries,
            totalStrokes: totalStrokes,
            correctStrokes: correctStrokes,
            incorrectStrokes: incorrectStrokes,
            perfectEntries: perfectEntries
        )
        metrics.characterMetrics = characterMetricsDict
        
        return metrics
    }
}
