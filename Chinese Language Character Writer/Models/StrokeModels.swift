import Foundation
import SwiftUI

// MARK: - Helper Types

/// Represents the direction of a stroke segment
struct StrokeDirection: Equatable {
    let dx: CGFloat
    let dy: CGFloat
    
    init(from start: CGPoint, to end: CGPoint) {
        self.dx = end.x - start.x
        self.dy = end.y - start.y
    }
    
    /// Calculates the angle (in radians) between this direction and another
    func angle(to other: StrokeDirection) -> CGFloat {
        let dot = dx * other.dx + dy * other.dy
        let det = dx * other.dy - dy * other.dx
        return atan2(det, dot)
    }
    
    /// The length of the direction vector
    var magnitude: CGFloat {
        return sqrt(dx * dx + dy * dy)
    }
}

/// Represents a single point in a stroke with timestamp
struct StrokePoint: Equatable {
    let location: CGPoint
    let timestamp: TimeInterval
    
    init(location: CGPoint, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.location = location
        self.timestamp = timestamp
    }
}

/// Represents a single stroke from touch down to lift
struct Stroke: Identifiable, Equatable {
    let id: UUID
    var points: [StrokePoint]
    var startTime: TimeInterval
    var endTime: TimeInterval
    private(set) var substrokes: [Substroke] = []
    
    /// A substroke is a continuous segment of a stroke that moves in a single direction
    struct Substroke: Identifiable, Equatable {
        let id: UUID
        let startIndex: Int
        let endIndex: Int
        let points: [StrokePoint]
        var normalizedCenter: CGPoint? = nil
        
        /// The direction vector of the substroke (from start to end)
        var direction: CGVector {
            guard let first = points.first, let last = points.last else {
                return .zero
            }
            return CGVector(dx: last.location.x - first.location.x,
                          dy: last.location.y - first.location.y)
        }
        
        /// The length of the substroke
        var magnitude: CGFloat {
            return sqrt(direction.dx * direction.dx + direction.dy * direction.dy)
        }
        
        /// The center point of the substroke's bounding box
        var center: CGPoint {
            let xs = points.map { $0.location.x }
            let ys = points.map { $0.location.y }
            guard !xs.isEmpty, !ys.isEmpty else { return .zero }
            
            let minX = xs.min() ?? 0
            let maxX = xs.max() ?? 0
            let minY = ys.min() ?? 0
            let maxY = ys.max() ?? 0
            
            return CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        }
        
        /// The angle of the substroke in radians in standard math orientation (0 = right, π/2 = up, π = left, 3π/2 = down)
        var angle: CGFloat {
            // In UIKit/SwiftUI, Y increases downward. Invert Y to match math convention (Y up).
            // Then normalize to [0, 2π), so a pure down stroke maps to 3π/2.
            let raw = atan2(-direction.dy, direction.dx)
            return raw >= 0 ? raw : raw + 2 * .pi
        }
        
        /// The normalized direction vector (unit vector)
        var normalizedDirection: CGVector {
            let mag = max(magnitude, .ulpOfOne) // Avoid division by zero
            return CGVector(dx: direction.dx / mag, dy: direction.dy / mag)
        }
        
        init(points: [StrokePoint], startIndex: Int, endIndex: Int) {
            self.id = UUID()
            self.points = points
            self.startIndex = startIndex
            self.endIndex = endIndex
            self.normalizedCenter = nil
        }
    }
    
    /// Detects corners in the stroke and splits it into substrokes
    /// - Parameter distanceThreshold: Minimum distance between points to consider for corner detection (default: 2.6)
    ///   Note: This should only be called after the stroke is complete for performance reasons
    internal mutating func detectSubstrokes(distanceThreshold: CGFloat = 2.6, cornerRatioThreshold: CGFloat = 1.1, curveRatioThreshold: CGFloat = 1.08) {
        // Handle cases with fewer than 3 points
        guard !points.isEmpty else { return }
        
        // For 1 or 2 points, create a single substroke
        if points.count <= 2 {
            substrokes = [Substroke(points: points, startIndex: 0, endIndex: points.count - 1)]
            return
        }
        
        var cornerIndices = [0] // Start with the first point
        
        // Find corners by analyzing angle changes
        for i in 1..<points.count-1 {
            let prevPoint = points[i-1].location
            let currPoint = points[i].location
            let nextPoint = points[i+1].location
            
            let d1 = CGPoint(x: (nextPoint.x - prevPoint.x), y: (nextPoint.y - prevPoint.y))
            let d2  = CGPoint(x: (currPoint.x - prevPoint.x), y: (currPoint.y - prevPoint.y))
            let d3 = CGPoint(x: (nextPoint.x - currPoint.x), y: (nextPoint.y - currPoint.y))
            
            let distance1 = sqrt(d1.x * d1.x + d1.y * d1.y)
            let distance2 = sqrt(d2.x * d2.x + d2.y * d2.y) + sqrt(d3.x * d3.x + d3.y * d3.y)
            
            
            let ratio = distance1 > 0 ? (distance2 / distance1) : 1.0
            if ratio > cornerRatioThreshold {
                cornerIndices.append(i)
            }
        }
        
        // Add the last point
        cornerIndices.append(points.count - 1)
        
        // Build prefix sums of arc length to enable O(1) segment length queries
        var prefixLen = Array(repeating: CGFloat(0), count: points.count)
        for i in 1..<points.count {
            let a = points[i-1].location
            let b = points[i].location
            prefixLen[i] = prefixLen[i-1] + sqrt((b.x - a.x)*(b.x - a.x) + (b.y - a.y)*(b.y - a.y))
        }
        
        // Insert extra pivots in segments that curve gradually (arc/chord > threshold)
        var extraPivots: [Int] = []
        if curveRatioThreshold > 1.0 {
            for seg in 0..<cornerIndices.count-1 {
                var segStart = cornerIndices[seg]
                let segEnd = cornerIndices[seg+1]
                var i = segStart + 1
                while i <= segEnd {
                    let run = prefixLen[i] - prefixLen[segStart]
                    let a = points[segStart].location
                    let b = points[i].location
                    let chord = sqrt((b.x - a.x)*(b.x - a.x) + (b.y - a.y)*(b.y - a.y))
                    if chord > 0, run / chord > curveRatioThreshold {
                        var mid = (segStart + i) / 2
                        if mid <= segStart { mid = segStart + 1 }
                        if mid >= segEnd { mid = segEnd - 1 }
                        if mid > segStart && mid < segEnd { extraPivots.append(mid) }
                        segStart = mid
                        i = segStart + 1
                    } else {
                        i += 1
                    }
                }
            }
        }
        
        // Merge and sort indices
        var all = Set(cornerIndices)
        for p in extraPivots { all.insert(p) }
        let indices = all.sorted()
        
        // Create substrokes between pivots
        var newSubstrokes: [Substroke] = []
        for i in 0..<indices.count-1 {
            let start = indices[i]
            let end = indices[i+1]
            if end >= start {
                let substrokePoints = Array(points[start...end])
                newSubstrokes.append(Substroke(points: substrokePoints, startIndex: start, endIndex: end))
            }
        }
        
        self.substrokes = newSubstrokes
    }

    /// Assigns normalized centers to each substroke using bounding-box normalization.
    /// Mapping: nx = (x - minX) / width, ny = (y - minY) / height, clamped to [0,1].
    /// - Parameter referenceRect: The rectangle to normalize against (typically the character bounding box)
    internal mutating func assignNormalizedCenters(relativeTo referenceRect: CGRect) {
        guard referenceRect.width > 0, referenceRect.height > 0 else { return }
        var updated: [Substroke] = []
        updated.reserveCapacity(substrokes.count)
        for var s in substrokes {
            let nx = (s.center.x - referenceRect.minX) / referenceRect.width
            let ny = (s.center.y - referenceRect.minY) / referenceRect.height
            // Clamp to [0,1] to ensure values are within bounds even with noise
            let clampedX = max(0, min(1, nx))
            let clampedY = max(0, min(1, ny))
            s.normalizedCenter = CGPoint(x: clampedX, y: clampedY)
            updated.append(s)
        }
        self.substrokes = updated
    }
    
    /// The bounding rectangle that contains all points in the stroke
    var boundingRect: CGRect {
        guard !points.isEmpty else { return .zero }
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        
        for point in points {
            minX = min(minX, point.location.x)
            minY = min(minY, point.location.y)
            maxX = max(maxX, point.location.x)
            maxY = max(maxY, point.location.y)
        }
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    /// Duration of the stroke in seconds
    var duration: TimeInterval {
        return endTime - startTime
    }
    
    init(id: UUID = UUID(), points: [StrokePoint] = []) {
        self.id = id
        self.points = points
        self.startTime = points.first?.timestamp ?? Date().timeIntervalSince1970
        self.endTime = points.last?.timestamp ?? Date().timeIntervalSince1970
    }
    
    /// Adds a new point to the stroke
    mutating func addPoint(_ point: StrokePoint) {
        points.append(point)
        endTime = point.timestamp
        if points.count == 1 {
            startTime = point.timestamp
        }
        // No substroke detection during drawing - deferred to endStroke()
    }
}

/// Represents a complete character composed of multiple strokes
struct CharacterDrawing: Identifiable, Equatable {
    let id: UUID
    var strokes: [Stroke]
    var startTime: TimeInterval
    var endTime: TimeInterval
    
    // MARK: - Computed Properties
    
    /// Total number of points across all strokes
    var totalPoints: Int {
        strokes.reduce(0) { $0 + $1.points.count }
    }
    
    /// Total number of substrokes
    var totalSubstrokes: Int {
        strokes.reduce(0) { $0 + $1.substrokes.count }
    }
    
    /// Average stroke speed in points per second
    var averageStrokeSpeed: Double {
        guard !strokes.isEmpty else { return 0 }
        let totalDuration = duration > 0 ? duration : 0.1 // Avoid division by zero
        return Double(totalPoints) / totalDuration
    }
    
    /// List of all substrokes across all strokes
    var allSubstrokes: [Stroke.Substroke] {
        strokes.flatMap { $0.substrokes }
    }
    
    /// The bounding rectangle that contains all strokes in the character
    var boundingRect: CGRect {
        guard !strokes.isEmpty else { return .zero }
        var result = strokes[0].boundingRect
        
        for stroke in strokes.dropFirst() {
            result = result.union(stroke.boundingRect)
        }
        return result
    }
    
    /// Duration of the entire character drawing in seconds
    var duration: TimeInterval {
        return endTime - startTime
    }
    
    /// Time between the end of the previous stroke and the start of the current one
    func timeSincePreviousStroke(at index: Int) -> TimeInterval? {
        guard index > 0, index < strokes.count else { return nil }
        return strokes[index].startTime - strokes[index - 1].endTime
    }
    
    init(id: UUID = UUID(), strokes: [Stroke] = []) {
        self.id = id
        self.strokes = strokes
        self.startTime = strokes.first?.startTime ?? Date().timeIntervalSince1970
        self.endTime = strokes.last?.endTime ?? Date().timeIntervalSince1970
    }
    
    /// Adds a new stroke to the character
    mutating func addStroke(_ stroke: Stroke) {
        strokes.append(stroke)
        endTime = stroke.endTime
        if strokes.count == 1 {
            startTime = stroke.startTime
        }
    }
    
    /// Removes the last stroke
    mutating func removeLastStroke() -> Stroke? {
        guard !strokes.isEmpty else { return nil }
        let removed = strokes.removeLast()
        endTime = strokes.last?.endTime ?? Date().timeIntervalSince1970
        return removed
    }
    
    /// Removes all strokes
    mutating func clear() {
        strokes.removeAll()
        let now = Date().timeIntervalSince1970
        startTime = now
        endTime = now
    }

    /// Compute the extended bounding box (adds 33% of width/height on each side)
    var extendedBoundingRect: CGRect {
        let rect = boundingRect
        let dx = rect.width * 0.33
        let dy = rect.height * 0.33
        // If rect has zero width/height, provide a minimal size to avoid division by zero downstream
        var extended = rect.insetBy(dx: -dx, dy: -dy)
        if extended.width == 0 { extended.size.width = 1 }
        if extended.height == 0 { extended.size.height = 1 }
        return extended
    }

    /// Bounding box computed from substroke centers (not ink), across all strokes
    var centerBasedBoundingRect: CGRect {
        let centers: [CGPoint] = strokes.flatMap { stroke in
            stroke.substrokes.map { $0.center }
        }
        guard !centers.isEmpty else { return .zero }
        let xs = centers.map { $0.x }
        let ys = centers.map { $0.y }
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        var rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if rect.width == 0 { rect.size.width = 1 }
        if rect.height == 0 { rect.size.height = 1 }
        return rect
    }

    /// Assign normalized centers for all substrokes in this character using the character bounding rect and its center
    mutating func assignNormalizedCentersToSubstrokes() {
        let ref = centerBasedBoundingRect
        for i in strokes.indices {
            strokes[i].assignNormalizedCenters(relativeTo: ref)
        }
    }
}

/// A view model to manage the drawing state
@MainActor
class DrawingViewModel: ObservableObject {
    @Published private(set) var currentStroke: Stroke?
    @Published private(set) var currentCharacter: CharacterDrawing
    @Published private(set) var characters: [CharacterDrawing] = []
    @Published var isRecordingSentence: Bool = false
    @Published private(set) var currentSentence: [CharacterDrawing] = []
    @Published private(set) var sentenceSubstrokes: [[Stroke.Substroke]] = []
    
    // Live-tunable substroke segmentation thresholds
    @Published var cornerRatioThreshold: CGFloat = 1.1
    @Published var curveRatioThreshold: CGFloat = 1.08
    
    // Point sampling settings
    private let minimumTimeInterval: TimeInterval = 0.05 // 50ms
    private let minimumDistanceSquared: CGFloat = 36.0 // 6 points squared (for efficiency)
    private var lastPointTime: TimeInterval = 0
    private var lastPoint: CGPoint?
    
    @Published var isInCharacterMode: Bool = false {
        didSet {
            if !isInCharacterMode && !currentCharacter.strokes.isEmpty {
                // Save the current character when exiting character mode
                characters.append(currentCharacter)
                currentCharacter = CharacterDrawing()
            }
        }
    }
    
    init() {
        self.currentCharacter = CharacterDrawing()
    }
    
    // MARK: - Public Methods
    
    /// Call this when a new touch begins
    func beginStroke(at location: CGPoint) {
        // If not in character mode, start a new character
        if !isInCharacterMode && !currentCharacter.strokes.isEmpty {
            characters.append(currentCharacter)
            currentCharacter = CharacterDrawing()
        }
        
        let now = Date().timeIntervalSince1970
        lastPointTime = now
        lastPoint = location
        
        let point = StrokePoint(location: location, timestamp: now)
        currentStroke = Stroke(points: [point])
    }
    
    /// Call this when the touch moves
    func continueStroke(at location: CGPoint) {
        guard var stroke = currentStroke else { return }
        
        let now = Date().timeIntervalSince1970
        let timeSinceLastPoint = now - lastPointTime
        
        // Check if enough time has passed and point is far enough from last point
        if timeSinceLastPoint >= minimumTimeInterval,
           let lastLocation = lastPoint,
           distanceSquared(from: lastLocation, to: location) >= minimumDistanceSquared {
            
            lastPointTime = now
            lastPoint = location
            
            let point = StrokePoint(location: location, timestamp: now)
            stroke.addPoint(point)
            currentStroke = stroke
        }
    }
    
    /// Calculate squared distance between two points (more efficient than calculating actual distance)
    private func distanceSquared(from point1: CGPoint, to point2: CGPoint) -> CGFloat {
        let dx = point2.x - point1.x
        let dy = point2.y - point1.y
        return dx * dx + dy * dy
    }
    
    /// Call this when the touch ends
    func endStroke() {
        guard var stroke = currentStroke, !stroke.points.isEmpty else {
            currentStroke = nil
            lastPoint = nil
            return
        }
        
        // Ensure we have at least 2 points for a valid stroke
        if stroke.points.count == 1, let lastLocation = lastPoint {
            // Add a second point slightly offset from the first if we only have one point
            stroke.addPoint(StrokePoint(location: CGPoint(x: lastLocation.x + 1, y: lastLocation.y + 1), 
                                     timestamp: Date().timeIntervalSince1970))
        }
        
        // Perform substroke detection for all strokes with 2+ points
        // Only process if we have enough points to make it worthwhile
        if stroke.points.count >= 2 {
            // Create a copy to avoid mutating the stroke while it's being used for drawing
            var strokeCopy = stroke
            strokeCopy.detectSubstrokes(
                distanceThreshold: 2.6,
                cornerRatioThreshold: cornerRatioThreshold,
                curveRatioThreshold: curveRatioThreshold
            )
            stroke = strokeCopy
        }
        
        // Add the processed stroke to the current character
        currentCharacter.addStroke(stroke)
        currentStroke = nil
    }
    
    /// Toggle character mode on/off
    func toggleCharacterMode() {
        isInCharacterMode.toggle()
    }
    
    /// Complete the current character and start a new one
    func completeCurrentCharacter() {
        guard !currentCharacter.strokes.isEmpty else { return }
        var finalized = currentCharacter
        finalized.assignNormalizedCentersToSubstrokes()
        characters.append(finalized)
        if isRecordingSentence {
            currentSentence.append(finalized)
            sentenceSubstrokes.append(finalized.allSubstrokes)
        }
        currentCharacter = CharacterDrawing()
    }
    
    /// Undo the last stroke or character
    func undo() -> (stroke: Stroke?, character: CharacterDrawing?) {
        if let stroke = currentCharacter.removeLastStroke() {
            return (stroke, nil)
        } else if let lastCharacter = characters.popLast() {
            return (nil, lastCharacter)
        }
        return (nil, nil)
    }
    
    /// Clear all strokes and characters
    func clear() {
        currentCharacter.clear()
        characters.removeAll()
        currentStroke = nil
        isRecordingSentence = false
        currentSentence.removeAll()
        sentenceSubstrokes.removeAll()
    }

    func startSentence() {
        isRecordingSentence = true
        currentSentence.removeAll()
        sentenceSubstrokes.removeAll()
    }

    func endSentence() -> ([[Stroke.Substroke]], [CharacterDrawing]) {
        isRecordingSentence = false
        return (sentenceSubstrokes, currentSentence)
    }
}
