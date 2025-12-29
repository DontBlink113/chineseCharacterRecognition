import Foundation

// MARK: - Parameter Set

/// A set of algorithm parameters to test
struct ParameterSet: Identifiable {
    let id = UUID()
    let errorThreshold: Double
    let distanceWeight: Double
    let lengthWeight: Double
    let temperature: Double
    let priorSigma: Double
    
    var accuracy: Double = 0
    var perfectEntryRate: Double = 0
    
    /// Description for display
    var description: String {
        """
        Error Threshold: \(String(format: "%.2f", errorThreshold))
        Distance Weight: \(String(format: "%.2f", distanceWeight))
        Length Weight: \(String(format: "%.2f", lengthWeight))
        Temperature: \(String(format: "%.2f", temperature))
        Prior Sigma: \(String(format: "%.2f", priorSigma))
        """
    }
}

// MARK: - Optimization Result

struct OptimizationResult {
    let bestParameters: ParameterSet
    let allResults: [ParameterSet]
    let totalCombinationsTested: Int
    let duration: TimeInterval
    
    var improvementOverDefault: Double {
        let defaultAccuracy = allResults.first(where: { 
            $0.errorThreshold == 0.5 && 
            $0.distanceWeight == 0.7 && 
            $0.lengthWeight == 0.3 
        })?.accuracy ?? 0
        
        return bestParameters.accuracy - defaultAccuracy
    }
}

// MARK: - Parameter Optimizer

class ParameterOptimizer: ObservableObject {
    @Published var isOptimizing = false
    @Published var progress: Double = 0
    @Published var currentTestDescription = ""
    @Published var optimizationResult: OptimizationResult?
    
    private var graphicsDataCache: [String: ReferenceCharacter]?
    
    /// Run optimization to find best parameters
    /// - Parameters:
    ///   - searchStrategy: The search strategy to use (grid, coarse, fine)
    func optimizeParameters(searchStrategy: SearchStrategy = .coarse) async {
        let startTime = Date()
        
        await MainActor.run {
            isOptimizing = true
            progress = 0
            currentTestDescription = "Loading validation data..."
            optimizationResult = nil
        }
        
        // Load graphics data once
        if graphicsDataCache == nil {
            graphicsDataCache = StrokeAnalyzer.loadGraphicsData()
        }
        
        // Load validation entries
        let entries: [ValidationEntry]
        do {
            entries = try ValidationDatasetManager.shared.loadEntries()
        } catch {
            print("Error loading validation entries: \(error)")
            await MainActor.run { isOptimizing = false }
            return
        }
        
        guard !entries.isEmpty else {
            await MainActor.run { isOptimizing = false }
            return
        }
        
        // Generate parameter combinations based on strategy
        let parameterSets = generateParameterSets(strategy: searchStrategy)
        
        await MainActor.run {
            currentTestDescription = "Testing \(parameterSets.count) parameter combinations..."
        }
        
        // Test each parameter set
        var results: [ParameterSet] = []
        
        for (index, params) in parameterSets.enumerated() {
            await MainActor.run {
                currentTestDescription = "Testing combination \(index + 1)/\(parameterSets.count)"
                progress = Double(index) / Double(parameterSets.count)
            }
            
            let result = testParameterSet(params, on: entries)
            results.append(result)
        }
        
        // Find best parameters
        let bestParams = results.max(by: { $0.accuracy < $1.accuracy }) ?? results[0]
        
        let duration = Date().timeIntervalSince(startTime)
        
        let finalResult = OptimizationResult(
            bestParameters: bestParams,
            allResults: results.sorted(by: { $0.accuracy > $1.accuracy }),
            totalCombinationsTested: parameterSets.count,
            duration: duration
        )
        
        await MainActor.run {
            optimizationResult = finalResult
            isOptimizing = false
            progress = 1.0
            currentTestDescription = "Optimization complete!"
        }
    }
    
    /// Test a single parameter set on all entries
    private func testParameterSet(_ params: ParameterSet, on entries: [ValidationEntry]) -> ParameterSet {
        var correctStrokes = 0
        var totalStrokes = 0
        var perfectEntries = 0
        
        for entry in entries {
            let result = validateEntry(entry, with: params)
            correctStrokes += result.correctCount
            totalStrokes += result.predictions.count
            if result.isCorrect {
                perfectEntries += 1
            }
        }
        
        var updatedParams = params
        updatedParams.accuracy = Double(correctStrokes) / Double(max(1, totalStrokes))
        updatedParams.perfectEntryRate = Double(perfectEntries) / Double(entries.count)
        
        return updatedParams
    }
    
    /// Validate a single entry with specific parameters
    private func validateEntry(_ entry: ValidationEntry, with params: ParameterSet) -> ValidationResult {
        // Convert LabeledStrokes to regular Strokes
        let userStrokes = entry.userStrokes.map { labeledStroke -> Stroke in
            let baseTimestamp = Date().timeIntervalSince1970
            let strokePoints = labeledStroke.points.enumerated().map { index, pointArray in
                let x = pointArray.count > 0 ? CGFloat(pointArray[0]) : 0
                let y = pointArray.count > 1 ? CGFloat(pointArray[1]) : 0
                return StrokePoint(
                    location: CGPoint(x: x, y: y),
                    timestamp: baseTimestamp + TimeInterval(index) * 0.01
                )
            }
            return Stroke(id: labeledStroke.id, points: strokePoints)
        }
        
        // Use cached graphics data
        let graphicsData = graphicsDataCache ?? StrokeAnalyzer.loadGraphicsData()
        
        guard let refChar = graphicsData[entry.character] else {
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
        
        let normalizedUserStrokes = StrokeAnalyzer.normalizeUserStrokes(userStrokes)
        
        var predictions: [Int?] = []
        
        for userStroke in normalizedUserStrokes {
            var errors: [Double] = []
            for refStroke in referenceStrokes {
                let error = StrokeAnalyzer.calculateError(
                    userStroke: userStroke,
                    referenceStroke: refStroke,
                    distanceWeight: params.distanceWeight,
                    lengthWeight: params.lengthWeight
                )
                errors.append(error)
            }
            
            let bestMatchIndex = errors.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            let rawError = errors[bestMatchIndex]
            let isMatched = rawError <= params.errorThreshold
            predictions.append(isMatched ? bestMatchIndex : nil)
        }
        
        let groundTruth = entry.userStrokes.map { $0.groundTruthMatch }
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
    
    /// Generate parameter combinations based on search strategy
    private func generateParameterSets(strategy: SearchStrategy) -> [ParameterSet] {
        switch strategy {
        case .quick:
            return generateQuickSearch()
        case .coarse:
            return generateCoarseSearch()
        case .fine:
            return generateFineSearch()
        case .exhaustive:
            return generateExhaustiveSearch()
        }
    }
    
    /// Quick search: Test a few key combinations (~10 tests)
    private func generateQuickSearch() -> [ParameterSet] {
        var sets: [ParameterSet] = []
        
        let errorThresholds: [Double] = [0.3, 0.5, 0.7]
        let distanceWeights: [Double] = [0.5, 0.7, 0.9]
        
        for errorThreshold in errorThresholds {
            for distanceWeight in distanceWeights {
                sets.append(ParameterSet(
                    errorThreshold: errorThreshold,
                    distanceWeight: distanceWeight,
                    lengthWeight: 1.0 - distanceWeight,
                    temperature: 0.1,
                    priorSigma: 2.0
                ))
            }
        }
        
        return sets
    }
    
    /// Coarse search: Test broader range (~50 tests)
    private func generateCoarseSearch() -> [ParameterSet] {
        var sets: [ParameterSet] = []
        
        let errorThresholds: [Double] = [0.2, 0.3, 0.4, 0.5, 0.6]
        let distanceWeights: [Double] = [0.5, 0.6, 0.7, 0.8, 0.9]
        let temperatures: [Double] = [0.05, 0.1, 0.2]
        
        for errorThreshold in errorThresholds {
            for distanceWeight in distanceWeights {
                for temperature in temperatures {
                    sets.append(ParameterSet(
                        errorThreshold: errorThreshold,
                        distanceWeight: distanceWeight,
                        lengthWeight: 1.0 - distanceWeight,
                        temperature: temperature,
                        priorSigma: 2.0
                    ))
                }
            }
        }
        
        return sets
    }
    
    /// Fine search: Test finer granularity (~200 tests)
    private func generateFineSearch() -> [ParameterSet] {
        var sets: [ParameterSet] = []
        
        let errorThresholds: [Double] = stride(from: 0.2, through: 0.8, by: 0.1).map { $0 }
        let distanceWeights: [Double] = stride(from: 0.5, through: 0.9, by: 0.05).map { $0 }
        let temperatures: [Double] = [0.05, 0.1, 0.15, 0.2]
        let priorSigmas: [Double] = [1.5, 2.0, 2.5]
        
        for errorThreshold in errorThresholds {
            for distanceWeight in distanceWeights {
                for temperature in temperatures {
                    for priorSigma in priorSigmas {
                        sets.append(ParameterSet(
                            errorThreshold: errorThreshold,
                            distanceWeight: distanceWeight,
                            lengthWeight: 1.0 - distanceWeight,
                            temperature: temperature,
                            priorSigma: priorSigma
                        ))
                    }
                }
            }
        }
        
        return sets
    }
    
    /// Exhaustive search: Test all combinations (~1000+ tests)
    private func generateExhaustiveSearch() -> [ParameterSet] {
        var sets: [ParameterSet] = []
        
        let errorThresholds: [Double] = stride(from: 0.1, through: 1.0, by: 0.05).map { $0 }
        let distanceWeights: [Double] = stride(from: 0.3, through: 1.0, by: 0.05).map { $0 }
        let temperatures: [Double] = stride(from: 0.01, through: 0.5, by: 0.05).map { $0 }
        let priorSigmas: [Double] = stride(from: 0.5, through: 5.0, by: 0.5).map { $0 }
        
        for errorThreshold in errorThresholds {
            for distanceWeight in distanceWeights {
                for temperature in temperatures {
                    for priorSigma in priorSigmas {
                        sets.append(ParameterSet(
                            errorThreshold: errorThreshold,
                            distanceWeight: distanceWeight,
                            lengthWeight: 1.0 - distanceWeight,
                            temperature: temperature,
                            priorSigma: priorSigma
                        ))
                    }
                }
            }
        }
        
        return sets
    }
}

// MARK: - Search Strategy

enum SearchStrategy: String, CaseIterable, Identifiable {
    case quick = "Quick"
    case coarse = "Coarse"
    case fine = "Fine"
    case exhaustive = "Exhaustive"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .quick:
            return "~10 tests, 30 seconds"
        case .coarse:
            return "~75 tests, 3-5 minutes"
        case .fine:
            return "~500 tests, 15-20 minutes"
        case .exhaustive:
            return "~10,000 tests, 3-5 hours"
        }
    }
}
