import Foundation
import SwiftUI

// MARK: - Reference Stroke Data Models

/// Represents reference stroke data from graphics.txt
struct ReferenceCharacter: Codable {
    let character: String
    let strokes: [String]
    let medians: [[[Double]]]
}

/// A parsed reference stroke with its median points and normalized SVG path
struct ReferenceStroke {
    let medianPoints: [CGPoint]
    let svgPath: String  // Normalized to [0,1] using same transform as medians
    
    /// Calculate the length of the stroke based on the sum of segment lengths
    var length: CGFloat {
        guard medianPoints.count >= 2 else { return 0 }
        var totalLength: CGFloat = 0
        for i in 1..<medianPoints.count {
            let dx = medianPoints[i].x - medianPoints[i-1].x
            let dy = medianPoints[i].y - medianPoints[i-1].y
            totalLength += sqrt(dx * dx + dy * dy)
        }
        return totalLength
    }
}

// MARK: - Stroke Analysis Result

/// Result of analyzing a single user stroke against all reference strokes
struct StrokeAnalysisResult {
    let userStrokeIndex: Int
    let probabilities: [Double] // Probability for each reference stroke
    let bestMatchIndex: Int?
    let bestMatchProbability: Double
    let rawError: Double // Raw error without prior
    let isMatched: Bool // False if error exceeds threshold
}

/// Complete analysis result for a character
struct CharacterAnalysisResult {
    let userStrokes: [Stroke]
    let referenceStrokes: [ReferenceStroke]
    let strokeResults: [StrokeAnalysisResult]
    
    /// Summary description for display
    var summaryText: String {
        var lines: [String] = []
        lines.append("User: \(strokeResults.count) strokes, Ref: \(referenceStrokes.count) strokes")
        lines.append("")
        for (idx, result) in strokeResults.enumerated() {
            let userIdx = idx + 1
            if result.isMatched, let matchIdx = result.bestMatchIndex {
                let prob = Int(result.bestMatchProbability * 100)
                lines.append("Stroke \(userIdx) → Ref \(matchIdx + 1) (\(prob)%, err: \(String(format: "%.3f", result.rawError)))")
            } else {
                lines.append("Stroke \(userIdx) → No match (error: \(String(format: "%.3f", result.rawError)))")
            }
        }
        return lines.joined(separator: "\n")
    }
    
    /// Detailed debug information
    var debugInfo: String {
        var lines: [String] = []
        for (idx, result) in strokeResults.enumerated() {
            lines.append("User Stroke \(idx + 1):")
            lines.append("  Top 3 matches:")
            let sorted = result.probabilities.enumerated().sorted { $0.element > $1.element }.prefix(3)
            for (refIdx, prob) in sorted {
                lines.append("    Ref \(refIdx + 1): \(Int(prob * 100))%")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Stroke Analyzer

class StrokeAnalyzer {
    
    // MARK: - Graphics.txt Loading
    
    /// Load and parse graphics.txt file
    static func loadGraphicsData() -> [String: ReferenceCharacter] {
        guard let url = Bundle.main.url(forResource: "graphics", withExtension: "txt") else {
            print("Error: graphics.txt not found")
            return [:]
        }
        
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            print("Error: Could not read graphics.txt")
            return [:]
        }
        
        var characterMap: [String: ReferenceCharacter] = [:]
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            guard !line.isEmpty else { continue }
            guard let data = line.data(using: .utf8) else { continue }
            
            do {
                let refChar = try JSONDecoder().decode(ReferenceCharacter.self, from: data)
                characterMap[refChar.character] = refChar
            } catch {
                // Skip malformed lines
                continue
            }
        }
        
        return characterMap
    }
    
    // MARK: - Coordinate Normalization
    
    /// Normalize coordinates from graphics.txt format to match user stroke coordinate system
    /// Graphics.txt uses a coordinate system where Y-axis is flipped
    /// Normalize to square [0,1] space preserving aspect ratio
    static func normalizeReferenceStrokes(_ medians: [[[Double]]], svgPaths: [String]) -> [ReferenceStroke] {
        // First, collect all points to find bounding box
        var allPoints: [CGPoint] = []
        for median in medians {
            for point in median {
                guard point.count >= 2 else { continue }
                allPoints.append(CGPoint(x: point[0], y: point[1]))
            }
        }
        
        guard !allPoints.isEmpty else { return [] }
        
        // Find bounding box
        let minX = allPoints.map { $0.x }.min() ?? 0
        let maxX = allPoints.map { $0.x }.max() ?? 1
        let minY = allPoints.map { $0.y }.min() ?? 0
        let maxY = allPoints.map { $0.y }.max() ?? 1
        
        let width = max(maxX - minX, 1)
        let height = max(maxY - minY, 1)
        
        // Use max dimension to preserve aspect ratio
        let scale = max(width, height)
        
        // Center in [0,1] space
        let offsetX = (scale - width) / 2
        let offsetY = (scale - height) / 2
        
        // Normalize each stroke
        var referenceStrokes: [ReferenceStroke] = []
        for (index, median) in medians.enumerated() {
            var normalizedPoints: [CGPoint] = []
            for point in median {
                guard point.count >= 2 else { continue }
                let x = (CGFloat(point[0]) - minX + offsetX) / scale
                // Flip Y-axis: graphics.txt has Y increasing downward, we want Y increasing upward
                let y = 1.0 - (CGFloat(point[1]) - minY + offsetY) / scale
                normalizedPoints.append(CGPoint(x: x, y: y))
            }
            
            // Get corresponding SVG path or empty string if index out of bounds
            let rawPath = index < svgPaths.count ? svgPaths[index] : ""
            let normalizedPath = normalizeSVGPathString(
                rawPath,
                minX: minX,
                minY: minY,
                scale: scale,
                offsetX: offsetX,
                offsetY: offsetY,
                flipY: true
            )
            
            referenceStrokes.append(ReferenceStroke(medianPoints: normalizedPoints, svgPath: normalizedPath))
        }
        
        return referenceStrokes
    }

    /// Normalize an SVG path string using the same transform as medians
    /// Supported commands: M, L, Q, C, Z (absolute)
    private static func normalizeSVGPathString(_ path: String,
                                               minX: CGFloat,
                                               minY: CGFloat,
                                               scale: CGFloat,
                                               offsetX: CGFloat,
                                               offsetY: CGFloat,
                                               flipY: Bool) -> String {
        guard !path.isEmpty else { return path }
        let parts = path.split(separator: " ")
        var i = 0
        var out: [String] = []
        func tx(_ x: Double, _ y: Double) -> (Double, Double) {
            let nx = (CGFloat(x) - minX + offsetX) / scale
            let ny0 = (CGFloat(y) - minY + offsetY) / scale
            let ny = flipY ? (1.0 - ny0) : ny0
            return (Double(nx), Double(ny))
        }
        func fmt(_ v: Double) -> String {
            // Limit to 6 decimal places to keep path compact
            return String(format: "%.6f", v).replacingOccurrences(of: "-0.000000", with: "0")
        }
        while i < parts.count {
            let cmd = String(parts[i])
            switch cmd {
            case "M":
                if i + 2 < parts.count, let x = Double(parts[i+1]), let y = Double(parts[i+2]) {
                    let (ux, uy) = tx(x, y)
                    out.append("M")
                    out.append(fmt(ux))
                    out.append(fmt(uy))
                    i += 3
                } else { out.append(cmd); i += 1 }
            case "L":
                if i + 2 < parts.count, let x = Double(parts[i+1]), let y = Double(parts[i+2]) {
                    let (ux, uy) = tx(x, y)
                    out.append("L")
                    out.append(fmt(ux))
                    out.append(fmt(uy))
                    i += 3
                } else { out.append(cmd); i += 1 }
            case "Q":
                if i + 4 < parts.count,
                   let x1 = Double(parts[i+1]), let y1 = Double(parts[i+2]),
                   let x = Double(parts[i+3]), let y = Double(parts[i+4]) {
                    let (ux1, uy1) = tx(x1, y1)
                    let (ux, uy) = tx(x, y)
                    out.append("Q")
                    out.append(fmt(ux1))
                    out.append(fmt(uy1))
                    out.append(fmt(ux))
                    out.append(fmt(uy))
                    i += 5
                } else { out.append(cmd); i += 1 }
            case "C":
                if i + 6 < parts.count,
                   let x1 = Double(parts[i+1]), let y1 = Double(parts[i+2]),
                   let x2 = Double(parts[i+3]), let y2 = Double(parts[i+4]),
                   let x = Double(parts[i+5]), let y = Double(parts[i+6]) {
                    let (ux1, uy1) = tx(x1, y1)
                    let (ux2, uy2) = tx(x2, y2)
                    let (ux, uy) = tx(x, y)
                    out.append("C")
                    out.append(fmt(ux1))
                    out.append(fmt(uy1))
                    out.append(fmt(ux2))
                    out.append(fmt(uy2))
                    out.append(fmt(ux))
                    out.append(fmt(uy))
                    i += 7
                } else { out.append(cmd); i += 1 }
            case "Z":
                out.append("Z")
                i += 1
            default:
                // Unknown or stray token; copy verbatim
                out.append(cmd)
                i += 1
            }
        }
        return out.joined(separator: " ")
    }
    
    /// Normalize user strokes to 0-1 range based on character bounding box
    /// Preserves aspect ratio by using square normalization
    static func normalizeUserStrokes(_ strokes: [Stroke], boundingBox: CGRect? = nil) -> [Stroke] {
        guard !strokes.isEmpty else { return [] }
        
        let minX: CGFloat
        let maxX: CGFloat
        let minY: CGFloat
        let maxY: CGFloat
        
        if let bbox = boundingBox {
            // Use provided bounding box
            minX = bbox.minX
            maxX = bbox.maxX
            minY = bbox.minY
            maxY = bbox.maxY
        } else {
            // Find bounding box of all strokes
            var allPoints: [CGPoint] = []
            for stroke in strokes {
                allPoints.append(contentsOf: stroke.points.map { $0.location })
            }
            
            guard !allPoints.isEmpty else { return [] }
            
            minX = allPoints.map { $0.x }.min() ?? 0
            maxX = allPoints.map { $0.x }.max() ?? 1
            minY = allPoints.map { $0.y }.min() ?? 0
            maxY = allPoints.map { $0.y }.max() ?? 1
        }
        
        let width = max(maxX - minX, 1)
        let height = max(maxY - minY, 1)
        
        // Use max dimension to preserve aspect ratio
        let scale = max(width, height)
        
        // Center in [0,1] space
        let offsetX = (scale - width) / 2
        let offsetY = (scale - height) / 2
        
        // Normalize each stroke
        var normalizedStrokes: [Stroke] = []
        for stroke in strokes {
            let normalizedPoints = stroke.points.map { point in
                let x = (point.location.x - minX + offsetX) / scale
                let y = (point.location.y - minY + offsetY) / scale
                return StrokePoint(location: CGPoint(x: x, y: y), timestamp: point.timestamp, pressure: point.pressure, speed: point.speed)
            }
            let normalizedDisplayPoints = stroke.displayPoints.map { point in
                let x = (point.location.x - minX + offsetX) / scale
                let y = (point.location.y - minY + offsetY) / scale
                return StrokePoint(location: CGPoint(x: x, y: y), timestamp: point.timestamp, pressure: point.pressure, speed: point.speed)
            }
            normalizedStrokes.append(Stroke(id: stroke.id, points: normalizedPoints, displayPoints: normalizedDisplayPoints))
        }
        
        return normalizedStrokes
    }
    
    // MARK: - Distance Calculation
    
    /// Calculate Fréchet distance between two curves
    /// This is the discrete Fréchet distance, which measures similarity between curves
    static func calculateFrechetDistance(userStroke: Stroke, referenceStroke: ReferenceStroke) -> Double {
        guard !userStroke.points.isEmpty, !referenceStroke.medianPoints.isEmpty else {
            return Double.infinity
        }
        
        let userPoints = userStroke.points.map { $0.location }
        let refPoints = referenceStroke.medianPoints
        
        let n = userPoints.count
        let m = refPoints.count
        
        // Dynamic programming table for Fréchet distance
        var dp = Array(repeating: Array(repeating: -1.0, count: m), count: n)
        
        func computeFrechet(_ i: Int, _ j: Int) -> Double {
            if dp[i][j] >= 0 {
                return dp[i][j]
            }
            
            let dx = Double(userPoints[i].x - refPoints[j].x)
            let dy = Double(userPoints[i].y - refPoints[j].y)
            let dist = sqrt(dx * dx + dy * dy)
            
            if i == 0 && j == 0 {
                dp[i][j] = dist
            } else if i == 0 {
                dp[i][j] = max(computeFrechet(i, j - 1), dist)
            } else if j == 0 {
                dp[i][j] = max(computeFrechet(i - 1, j), dist)
            } else {
                let minPrev = min(computeFrechet(i - 1, j),
                                 min(computeFrechet(i, j - 1),
                                     computeFrechet(i - 1, j - 1)))
                dp[i][j] = max(minPrev, dist)
            }
            
            return dp[i][j]
        }
        
        return computeFrechet(n - 1, m - 1)
    }
    
    /// Calculate bidirectional Hausdorff-like distance between strokes (legacy)
    /// Measures how close the user stroke follows the reference stroke path
    static func calculateAverageDistance(userStroke: Stroke, referenceStroke: ReferenceStroke) -> Double {
        guard !userStroke.points.isEmpty, !referenceStroke.medianPoints.isEmpty else {
            return Double.infinity
        }
        
        // Direction 1: For each reference point, find closest user point
        var refToUser: Double = 0
        for refPoint in referenceStroke.medianPoints {
            var minDist = Double.infinity
            for userPoint in userStroke.points {
                let dx = Double(userPoint.location.x - refPoint.x)
                let dy = Double(userPoint.location.y - refPoint.y)
                let dist = sqrt(dx * dx + dy * dy)
                minDist = min(minDist, dist)
            }
            refToUser += minDist
        }
        refToUser /= Double(referenceStroke.medianPoints.count)
        
        // Direction 2: For each user point, find closest reference point
        // Sample user points to avoid overwhelming computation
        let sampleRate = max(1, userStroke.points.count / 20) // Sample ~20 points
        var userToRef: Double = 0
        var sampleCount = 0
        for (idx, userPoint) in userStroke.points.enumerated() {
            if idx % sampleRate == 0 {
                var minDist = Double.infinity
                for refPoint in referenceStroke.medianPoints {
                    let dx = Double(userPoint.location.x - refPoint.x)
                    let dy = Double(userPoint.location.y - refPoint.y)
                    let dist = sqrt(dx * dx + dy * dy)
                    minDist = min(minDist, dist)
                }
                userToRef += minDist
                sampleCount += 1
            }
        }
        userToRef /= Double(max(1, sampleCount))
        
        // Return average of both directions
        return (refToUser + userToRef) / 2.0
    }
    
    /// Calculate length difference between user stroke and reference stroke
    static func calculateLengthDifference(userStroke: Stroke, referenceStroke: ReferenceStroke) -> Double {
        let userLength = calculateStrokeLength(userStroke)
        let refLength = Double(referenceStroke.length)
        
        guard refLength > 0 else { return Double.infinity }
        
        // Return relative difference
        return abs(userLength - refLength) / refLength
    }
    
    /// Calculate the length of a user stroke
    static func calculateStrokeLength(_ stroke: Stroke) -> Double {
        guard stroke.points.count >= 2 else { return 0 }
        
        var totalLength: Double = 0
        for i in 1..<stroke.points.count {
            let dx = Double(stroke.points[i].location.x - stroke.points[i-1].location.x)
            let dy = Double(stroke.points[i].location.y - stroke.points[i-1].location.y)
            totalLength += sqrt(dx * dx + dy * dy)
        }
        return totalLength
    }
    
    // MARK: - Error Calculation
    
    /// Calculate error using Fréchet distance (baseline algorithm)
    static func calculateFrechetError(userStroke: Stroke, referenceStroke: ReferenceStroke) -> Double {
        return calculateFrechetDistance(userStroke: userStroke, referenceStroke: referenceStroke)
    }
    
    /// Calculate combined error between user stroke and reference stroke (legacy)
    /// Error = w1 * avgDistance + w2 * lengthDifference
    static func calculateError(userStroke: Stroke, referenceStroke: ReferenceStroke,
                              distanceWeight: Double = 0.7, lengthWeight: Double = 0.3) -> Double {
        let avgDistance = calculateAverageDistance(userStroke: userStroke, referenceStroke: referenceStroke)
        let lengthDiff = calculateLengthDifference(userStroke: userStroke, referenceStroke: referenceStroke)
        
        return distanceWeight * avgDistance + lengthWeight * lengthDiff
    }
    
    // MARK: - Decomposed Error Calculation
    
    /// Result of decomposed stroke comparison
    /// Contains separate error components for shape, size, position, and angle
    struct DecomposedError {
        let shapeError: Double      // Fréchet distance after optimal alignment (pure shape difference)
        let sizeError: Double       // Scale factor needed (1.0 = same size, 2.0 = user is 2x larger)
        let distanceError: Double   // Translation distance needed to align centroids
        let angleError: Double      // Rotation angle needed in radians (absolute value)
        
        /// Combined weighted error
        func combinedError(shapeWeight: Double = 0.4,
                          sizeWeight: Double = 0.2,
                          distanceWeight: Double = 0.2,
                          angleWeight: Double = 0.2) -> Double {
            return shapeWeight * shapeError +
                   sizeWeight * sizeError +
                   distanceWeight * distanceError +
                   angleWeight * angleError
        }
    }
    
    /// Calculate decomposed error between user stroke and reference stroke
    /// Finds optimal alignment (translation, rotation, scale) then measures residual shape error
    static func calculateDecomposedError(userStroke: Stroke, referenceStroke: ReferenceStroke) -> DecomposedError {
        let userPoints = userStroke.points.map { $0.location }
        let refPoints = referenceStroke.medianPoints
        
        guard userPoints.count >= 2, refPoints.count >= 2 else {
            return DecomposedError(shapeError: Double.infinity, sizeError: Double.infinity,
                                   distanceError: Double.infinity, angleError: Double.infinity)
        }
        
        // Step 1: Calculate centroids
        let userCentroid = calculateCentroid(userPoints)
        let refCentroid = calculateCentroid(refPoints)
        
        // Distance error: Euclidean distance between centroids
        let distanceError = sqrt(pow(userCentroid.x - refCentroid.x, 2) + 
                                 pow(userCentroid.y - refCentroid.y, 2))
        
        // Step 2: Translate both to origin (center on centroid)
        let userCentered = userPoints.map { CGPoint(x: $0.x - userCentroid.x, y: $0.y - userCentroid.y) }
        let refCentered = refPoints.map { CGPoint(x: $0.x - refCentroid.x, y: $0.y - refCentroid.y) }
        
        // Step 3: Calculate sizes (RMS distance from centroid)
        let userSize = calculateRMSSize(userCentered)
        let refSize = calculateRMSSize(refCentered)
        
        // Size error: ratio of sizes (how much to scale user to match ref)
        let sizeRatio = refSize > 0.0001 ? userSize / refSize : 1.0
        let sizeError = abs(log(max(sizeRatio, 0.001)))  // Log scale so 2x and 0.5x have same error
        
        // Step 4: Normalize both to unit size
        let userNormalized = userSize > 0.0001 ? userCentered.map { CGPoint(x: $0.x / userSize, y: $0.y / userSize) } : userCentered
        let refNormalized = refSize > 0.0001 ? refCentered.map { CGPoint(x: $0.x / refSize, y: $0.y / refSize) } : refCentered
        
        // Step 5: Find optimal rotation angle using Procrustes analysis
        let optimalAngle = calculateOptimalRotation(from: userNormalized, to: refNormalized)
        let angleError = abs(optimalAngle)  // Absolute rotation needed
        
        // Step 6: Rotate user stroke by optimal angle
        let userRotated = rotatePoints(userNormalized, by: optimalAngle)
        
        // Step 7: Calculate shape error (Fréchet distance after alignment)
        let shapeError = calculateFrechetDistancePoints(userRotated, refNormalized)
        
        return DecomposedError(shapeError: shapeError, sizeError: sizeError,
                               distanceError: distanceError, angleError: angleError)
    }
    
    /// Calculate centroid of a set of points
    private static func calculateCentroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sumX = points.reduce(0.0) { $0 + $1.x }
        let sumY = points.reduce(0.0) { $0 + $1.y }
        return CGPoint(x: sumX / CGFloat(points.count), y: sumY / CGFloat(points.count))
    }
    
    /// Calculate RMS (root mean square) distance from origin - represents "size" of stroke
    private static func calculateRMSSize(_ points: [CGPoint]) -> CGFloat {
        guard !points.isEmpty else { return 0 }
        let sumSquares = points.reduce(0.0) { $0 + $1.x * $1.x + $1.y * $1.y }
        return sqrt(sumSquares / CGFloat(points.count))
    }
    
    /// Find optimal rotation angle to align source points to target points
    /// Uses Procrustes analysis: minimize sum of squared distances
    private static func calculateOptimalRotation(from source: [CGPoint], to target: [CGPoint]) -> Double {
        // Resample both to same number of points for comparison
        let numSamples = 20
        let sourceSampled = resamplePoints(source, to: numSamples)
        let targetSampled = resamplePoints(target, to: numSamples)
        
        // Calculate optimal rotation using SVD-like approach
        // For 2D, this simplifies to: theta = atan2(sum(x_s * y_t - y_s * x_t), sum(x_s * x_t + y_s * y_t))
        var crossSum: Double = 0  // sum of cross products
        var dotSum: Double = 0    // sum of dot products
        
        for i in 0..<numSamples {
            let sx = Double(sourceSampled[i].x)
            let sy = Double(sourceSampled[i].y)
            let tx = Double(targetSampled[i].x)
            let ty = Double(targetSampled[i].y)
            
            crossSum += sx * ty - sy * tx
            dotSum += sx * tx + sy * ty
        }
        
        return atan2(crossSum, dotSum)
    }
    
    /// Rotate points by given angle (in radians)
    private static func rotatePoints(_ points: [CGPoint], by angle: Double) -> [CGPoint] {
        let cosA = cos(angle)
        let sinA = sin(angle)
        return points.map { p in
            CGPoint(x: CGFloat(Double(p.x) * cosA - Double(p.y) * sinA),
                    y: CGFloat(Double(p.x) * sinA + Double(p.y) * cosA))
        }
    }
    
    /// Resample a polyline to have exactly n points, evenly spaced by arc length
    private static func resamplePoints(_ points: [CGPoint], to n: Int) -> [CGPoint] {
        guard points.count >= 2, n >= 2 else { return points }
        
        // Calculate total length and segment lengths
        var lengths: [CGFloat] = [0]
        for i in 1..<points.count {
            let dx = points[i].x - points[i-1].x
            let dy = points[i].y - points[i-1].y
            lengths.append(lengths.last! + sqrt(dx * dx + dy * dy))
        }
        
        let totalLength = lengths.last!
        guard totalLength > 0 else { return Array(repeating: points[0], count: n) }
        
        // Resample at even intervals
        var resampled: [CGPoint] = []
        let step = totalLength / CGFloat(n - 1)
        
        for i in 0..<n {
            let targetDist = CGFloat(i) * step
            
            // Find segment containing this distance
            var segIdx = 0
            while segIdx < lengths.count - 1 && lengths[segIdx + 1] < targetDist {
                segIdx += 1
            }
            
            if segIdx >= points.count - 1 {
                resampled.append(points.last!)
            } else {
                let segLength = lengths[segIdx + 1] - lengths[segIdx]
                let t = segLength > 0 ? (targetDist - lengths[segIdx]) / segLength : 0
                let p = CGPoint(
                    x: points[segIdx].x + t * (points[segIdx + 1].x - points[segIdx].x),
                    y: points[segIdx].y + t * (points[segIdx + 1].y - points[segIdx].y)
                )
                resampled.append(p)
            }
        }
        
        return resampled
    }
    
    /// Calculate Fréchet distance between two point arrays
    private static func calculateFrechetDistancePoints(_ points1: [CGPoint], _ points2: [CGPoint]) -> Double {
        guard !points1.isEmpty, !points2.isEmpty else { return Double.infinity }
        
        let n = points1.count
        let m = points2.count
        
        var dp = Array(repeating: Array(repeating: -1.0, count: m), count: n)
        
        func computeFrechet(_ i: Int, _ j: Int) -> Double {
            if dp[i][j] >= 0 { return dp[i][j] }
            
            let dx = Double(points1[i].x - points2[j].x)
            let dy = Double(points1[i].y - points2[j].y)
            let dist = sqrt(dx * dx + dy * dy)
            
            if i == 0 && j == 0 {
                dp[i][j] = dist
            } else if i == 0 {
                dp[i][j] = max(computeFrechet(i, j - 1), dist)
            } else if j == 0 {
                dp[i][j] = max(computeFrechet(i - 1, j), dist)
            } else {
                let minPrev = min(computeFrechet(i - 1, j),
                                 min(computeFrechet(i, j - 1),
                                     computeFrechet(i - 1, j - 1)))
                dp[i][j] = max(minPrev, dist)
            }
            
            return dp[i][j]
        }
        
        return computeFrechet(n - 1, m - 1)
    }
    
    // MARK: - Prior Probability
    
    /// Calculate prior probability based on stroke order
    /// Prior is highest when userStrokeIndex == referenceStrokeIndex, and decreases with distance
    static func calculatePrior(userStrokeIndex: Int, referenceStrokeIndex: Int, 
                               totalReferenceStrokes: Int, sigma: Double = 2.0) -> Double {
        let distance = abs(userStrokeIndex - referenceStrokeIndex)
        // Gaussian prior centered at correct index
        return exp(-Double(distance * distance) / (2 * sigma * sigma))
    }
    
    // MARK: - Optimal Assignment Algorithm
    
    /// Configuration for decomposed error weights
    struct ErrorWeights {
        var shapeWeight: Double = 0
        var sizeWeight: Double = 0.1
        var distanceWeight: Double = 0.6
        var angleWeight: Double = 0.3
        
        static let `default` = ErrorWeights()
        static let shapeOnly = ErrorWeights(shapeWeight: 1.0, sizeWeight: 0.0, distanceWeight: 0.0, angleWeight: 0.0)
        static let noAngle = ErrorWeights(shapeWeight: 0.5, sizeWeight: 0.25, distanceWeight: 0.25, angleWeight: 0.0)
    }
    
    /// Find optimal stroke assignment that maximizes total posterior probability
    /// Uses Hungarian algorithm approach for maximum weight bipartite matching
    /// Returns array where index is user stroke index, value is assigned reference stroke index (or nil if unassigned)
    static func findOptimalAssignment(userStrokes: [Stroke], 
                                     referenceStrokes: [ReferenceStroke],
                                     priorSigma: Double = 2.0,
                                     useUniformPrior: Bool = true,
                                     errorThreshold: Double = Double.infinity,
                                     useDecomposedError: Bool = true,
                                     errorWeights: ErrorWeights = .default) -> [Int?] {
        let numUser = userStrokes.count
        let numRef = referenceStrokes.count
        
        guard numUser > 0 && numRef > 0 else {
            return Array(repeating: nil, count: numUser)
        }
        
        // Step 1: Calculate error for each (user stroke, reference stroke) pair
        var errorMatrix: [[Double]] = []
        var decomposedMatrix: [[DecomposedError]] = []  // Store decomposed errors for debugging
        
        for userStroke in userStrokes {
            var errorRow: [Double] = []
            var decomposedRow: [DecomposedError] = []
            
            for refStroke in referenceStrokes {
                if useDecomposedError {
                    let decomposed = calculateDecomposedError(userStroke: userStroke, referenceStroke: refStroke)
                    decomposedRow.append(decomposed)
                    let combinedError = decomposed.combinedError(
                        shapeWeight: errorWeights.shapeWeight,
                        sizeWeight: errorWeights.sizeWeight,
                        distanceWeight: errorWeights.distanceWeight,
                        angleWeight: errorWeights.angleWeight
                    )
                    errorRow.append(combinedError)
                } else {
                    // Legacy: use raw Fréchet distance
                    let frechetDist = calculateFrechetDistance(userStroke: userStroke, referenceStroke: refStroke)
                    errorRow.append(frechetDist)
                    decomposedRow.append(DecomposedError(shapeError: frechetDist, sizeError: 0, distanceError: 0, angleError: 0))
                }
            }
            errorMatrix.append(errorRow)
            decomposedMatrix.append(decomposedRow)
        }
        
        // Step 2: Find min error for each user stroke and filter out strokes above threshold
        var validUserIndices: [Int] = []
        for userIdx in 0..<numUser {
            let minError = errorMatrix[userIdx].min() ?? Double.infinity
            if minError <= errorThreshold {
                validUserIndices.append(userIdx)
            }
        }
        
        // If no valid strokes, return all nil
        guard !validUserIndices.isEmpty else {
            return Array(repeating: nil, count: numUser)
        }
        
        // Step 3: Build posterior matrix only for valid strokes
        var posteriorMatrix: [[Double]] = []
        for userIdx in validUserIndices {
            var row: [Double] = []
            for refIdx in 0..<numRef {
                let error = errorMatrix[userIdx][refIdx]
                
                // Convert error to likelihood (smaller error = higher likelihood)
                // Use temperature scaling to control sharpness of distribution
                let temperature = 0.5  // Lower = sharper distinction between good/bad matches
                let likelihood = exp(-error / temperature)
                
                // Calculate prior based on stroke order (or use uniform prior)
                let prior: Double
                if useUniformPrior {
                    prior = 1.0 / Double(numRef)
                } else {
                    prior = calculatePrior(userStrokeIndex: userIdx, 
                                          referenceStrokeIndex: refIdx,
                                          totalReferenceStrokes: numRef,
                                          sigma: priorSigma)
                }
                
                // Posterior = likelihood × prior
                let posterior = likelihood * prior
                row.append(posterior)
            }
            posteriorMatrix.append(row)
        }
        
        // Step 4: Run Hungarian on valid strokes only
        let validAssignments = hungarianAlgorithm(posteriorMatrix: posteriorMatrix, numUser: validUserIndices.count, numRef: numRef)
        
        // Step 5: Map back to original indices
        var assignments: [Int?] = Array(repeating: nil, count: numUser)
        for (i, userIdx) in validUserIndices.enumerated() {
            assignments[userIdx] = validAssignments[i]
        }
        
        return assignments
    }
    
    /// Hungarian algorithm for optimal bipartite matching
    /// Finds the assignment that maximizes total posterior probability
    /// - Parameters:
    ///   - posteriorMatrix: Matrix where posteriorMatrix[i][j] = P(user_i matches ref_j)
    ///   - numUser: Number of user strokes
    ///   - numRef: Number of reference strokes
    /// - Returns: Array where index is user stroke index, value is assigned reference stroke index (or nil)
    private static func hungarianAlgorithm(posteriorMatrix: [[Double]], numUser: Int, numRef: Int) -> [Int?] {
        // Handle edge cases
        guard numUser > 0 && numRef > 0 else {
            return Array(repeating: nil, count: numUser)
        }
        
        // Create square cost matrix (we minimize cost, so use negative posterior)
        // Pad to make it square if needed
        let n = max(numUser, numRef)
        var cost = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        
        // Find max posterior for normalization to avoid numerical issues
        var maxPosterior = 0.0
        for i in 0..<numUser {
            for j in 0..<numRef {
                maxPosterior = max(maxPosterior, posteriorMatrix[i][j])
            }
        }
        
        // Fill cost matrix: cost = maxPosterior - posterior (to convert max to min problem)
        for i in 0..<n {
            for j in 0..<n {
                if i < numUser && j < numRef {
                    cost[i][j] = maxPosterior - posteriorMatrix[i][j]
                } else {
                    // Dummy rows/columns get max cost
                    cost[i][j] = maxPosterior
                }
            }
        }
        
        // Hungarian algorithm (Kuhn-Munkres)
        // u[i] and v[j] are potentials for rows and columns
        var u = Array(repeating: 0.0, count: n + 1)
        var v = Array(repeating: 0.0, count: n + 1)
        // p[j] = row assigned to column j (1-indexed, 0 means unassigned)
        var p = Array(repeating: 0, count: n + 1)
        // way[j] = previous column in alternating path
        var way = Array(repeating: 0, count: n + 1)
        
        for i in 1...n {
            // Start augmenting path from row i
            p[0] = i
            var j0 = 0  // Current column (0 is virtual)
            var minv = Array(repeating: Double.infinity, count: n + 1)
            var used = Array(repeating: false, count: n + 1)
            
            repeat {
                used[j0] = true
                let i0 = p[j0]
                var delta = Double.infinity
                var j1 = 0
                
                for j in 1...n {
                    if !used[j] {
                        let cur = cost[i0 - 1][j - 1] - u[i0] - v[j]
                        if cur < minv[j] {
                            minv[j] = cur
                            way[j] = j0
                        }
                        if minv[j] < delta {
                            delta = minv[j]
                            j1 = j
                        }
                    }
                }
                
                // Update potentials
                for j in 0...n {
                    if used[j] {
                        u[p[j]] += delta
                        v[j] -= delta
                    } else {
                        minv[j] -= delta
                    }
                }
                
                j0 = j1
            } while p[j0] != 0
            
            // Reconstruct path
            repeat {
                let j1 = way[j0]
                p[j0] = p[j1]
                j0 = j1
            } while j0 != 0
        }
        
        // Extract assignments (p[j] = row assigned to column j)
        var assignments: [Int?] = Array(repeating: nil, count: numUser)
        for j in 1...n {
            let row = p[j] - 1  // Convert back to 0-indexed
            let col = j - 1
            if row >= 0 && row < numUser && col < numRef {
                assignments[row] = col
            }
        }
        
        return assignments
    }
    
    // MARK: - Softmax Probability
    
    /// Calculate softmax probability distribution over all reference strokes
    /// P(ref_i | user_j) ∝ prior(i,j) * exp(-error(user_j, ref_i))
    static func calculateProbabilities(userStrokeIndex: Int, userStroke: Stroke,
                                      referenceStrokes: [ReferenceStroke],
                                      temperature: Double = 0.1) -> [Double] {
        return calculateProbabilitiesWithParams(
            userStrokeIndex: userStrokeIndex,
            userStroke: userStroke,
            referenceStrokes: referenceStrokes,
            temperature: temperature,
            priorSigma: 2.0,
            distanceWeight: 0.7,
            lengthWeight: 0.3
        )
    }
    
    /// Calculate probabilities with all tunable parameters
    static func calculateProbabilitiesWithParams(userStrokeIndex: Int, 
                                                 userStroke: Stroke,
                                                 referenceStrokes: [ReferenceStroke],
                                                 temperature: Double,
                                                 priorSigma: Double,
                                                 distanceWeight: Double,
                                                 lengthWeight: Double) -> [Double] {
        var logits: [Double] = []
        
        for (refIndex, refStroke) in referenceStrokes.enumerated() {
            let error = calculateError(
                userStroke: userStroke, 
                referenceStroke: refStroke,
                distanceWeight: distanceWeight,
                lengthWeight: lengthWeight
            )
            let prior = calculatePrior(
                userStrokeIndex: userStrokeIndex, 
                referenceStrokeIndex: refIndex,
                totalReferenceStrokes: referenceStrokes.count,
                sigma: priorSigma
            )
            
            // Log probability: log(prior) - error/temperature
            let logProb = log(prior + 1e-10) - error / temperature
            logits.append(logProb)
        }
        
        // Apply softmax
        let maxLogit = logits.max() ?? 0
        let expLogits = logits.map { exp($0 - maxLogit) }
        let sumExp = expLogits.reduce(0, +)
        
        return expLogits.map { $0 / sumExp }
    }
    
    // MARK: - Main Analysis Function
    
    /// Analyze user strokes against reference strokes for a character using baseline algorithm
    /// Uses Fréchet distance and optimal assignment based on maximum posterior probability
    /// - Parameters:
    ///   - userStrokes: The strokes drawn by the user
    ///   - character: The target character
    ///   - priorSigma: Standard deviation for stroke order prior (default: 2.0)
    ///   - useUniformPrior: If true, uses uniform prior instead of Gaussian (default: true for no stroke order preference)
    ///   - boundingBox: Optional bounding box to use for normalization (if nil, uses stroke bounds)
    /// - Returns: Analysis result or nil if character not found
    static func analyzeCharacter(userStrokes: [Stroke], 
                                character: String, 
                                priorSigma: Double = 2.0,
                                useUniformPrior: Bool = true,
                                boundingBox: CGRect? = nil,
                                errorThreshold: Double = 0.35) -> CharacterAnalysisResult? {
        // Load graphics data
        let graphicsData = loadGraphicsData()
        
        guard let refChar = graphicsData[character] else {
            print("No reference data found for character: \(character)")
            return nil
        }
        
        // Parse reference strokes
        let referenceStrokes = normalizeReferenceStrokes(refChar.medians, svgPaths: refChar.strokes)
        
        guard !referenceStrokes.isEmpty else {
            print("No reference strokes found")
            return nil
        }
        
        // Normalize user strokes with optional bounding box
        let normalizedUserStrokes = normalizeUserStrokes(userStrokes, boundingBox: boundingBox)
        
        // Use optimal assignment algorithm (baseline)
        let assignments = findOptimalAssignment(
            userStrokes: normalizedUserStrokes,
            referenceStrokes: referenceStrokes,
            priorSigma: priorSigma,
            useUniformPrior: useUniformPrior,
            errorThreshold: errorThreshold
        )
        
        // Build stroke results based on assignments
        var strokeResults: [StrokeAnalysisResult] = []
        
        for (userIdx, userStroke) in normalizedUserStrokes.enumerated() {
            let assignedRefIdx = assignments[userIdx]
            
            // Calculate Fréchet distances to all reference strokes for display
            var frechetDistances: [Double] = []
            for refStroke in referenceStrokes {
                let dist = calculateFrechetDistance(userStroke: userStroke, referenceStroke: refStroke)
                frechetDistances.append(dist)
            }
            
            // Calculate posterior probabilities for display
            var probabilities: [Double] = []
            for (refIdx, refStroke) in referenceStrokes.enumerated() {
                let frechetDist = frechetDistances[refIdx]
                let likelihood = exp(-frechetDist)
                let prior: Double
                if useUniformPrior {
                    prior = 1.0 / Double(referenceStrokes.count)  // Uniform prior (no stroke order preference)
                } else {
                    prior = calculatePrior(
                        userStrokeIndex: userIdx,
                        referenceStrokeIndex: refIdx,
                        totalReferenceStrokes: referenceStrokes.count,
                        sigma: priorSigma
                    )
                }
                probabilities.append(likelihood * prior)
            }
            
            // Normalize probabilities
            let sumProb = probabilities.reduce(0, +)
            if sumProb > 0 {
                probabilities = probabilities.map { $0 / sumProb }
            }
            
            // Get raw error and probability for assigned match
            let rawError: Double
            let bestMatchProbability: Double
            let bestMatchIndexFinal: Int?
            let isMatched: Bool
            
            if let refIdx = assignedRefIdx {
                let err = frechetDistances[refIdx]
                rawError = err
                bestMatchProbability = probabilities[refIdx]
                if err <= errorThreshold {
                    bestMatchIndexFinal = refIdx
                    isMatched = true
                } else {
                    bestMatchIndexFinal = nil
                    isMatched = false
                }
            } else {
                rawError = frechetDistances.min() ?? Double.infinity
                bestMatchProbability = 0.0
                bestMatchIndexFinal = nil
                isMatched = false
            }
            
            strokeResults.append(StrokeAnalysisResult(
                userStrokeIndex: userIdx,
                probabilities: probabilities,
                bestMatchIndex: bestMatchIndexFinal,
                bestMatchProbability: bestMatchProbability,
                rawError: rawError,
                isMatched: isMatched
            ))
        }
        
        return CharacterAnalysisResult(
            userStrokes: userStrokes,
            referenceStrokes: referenceStrokes,
            strokeResults: strokeResults
        )
    }
}
