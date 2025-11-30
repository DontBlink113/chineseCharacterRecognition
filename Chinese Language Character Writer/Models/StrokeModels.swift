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

/// Represents a single point in a stroke with timestamp and optional force/pressure
struct StrokePoint: Equatable {
    let location: CGPoint
    let timestamp: TimeInterval
    let force: CGFloat?
    
    init(location: CGPoint, timestamp: TimeInterval = Date().timeIntervalSince1970, force: CGFloat? = nil) {
        self.location = location
        self.timestamp = timestamp
        self.force = force
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
        
        /// The angle of the substroke in radians (0 to 2π)
        var angle: CGFloat {
            return atan2(direction.dy, direction.dx)
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
        }
    }
    
    /// Detects corners in the stroke and splits it into substrokes
    /// - Parameter angleThreshold: Minimum angle (in radians) to consider a corner (default: 0.5)
    /// - Parameter distanceThreshold: Minimum distance between points to consider for corner detection (default: 5.0)
    mutating func detectSubstrokes(angleThreshold: CGFloat = 0.5, distanceThreshold: CGFloat = 5.0) {
        guard points.count >= 3 else {
            // Not enough points to detect corners
            if !points.isEmpty {
                substrokes = [Substroke(points: points, startIndex: 0, endIndex: points.count - 1)]
            }
            return
        }
        
        var cornerIndices = [0] // Start with the first point
        
        // Find corners by analyzing angle changes
        for i in 1..<points.count-1 {
            let prevPoint = points[i-1].location
            let currPoint = points[i].location
            let nextPoint = points[i+1].location
            
            let d1 = CGPoint(x: currPoint.x - prevPoint.x, y: currPoint.y - prevPoint.y)
            let d2 = CGPoint(x: nextPoint.x - currPoint.x, y: nextPoint.y - currPoint.y)
            
            // Skip if points are too close
            let d1Length = sqrt(d1.x * d1.x + d1.y * d1.y)
            let d2Length = sqrt(d2.x * d2.x + d2.y * d2.y)
            guard d1Length > distanceThreshold && d2Length > distanceThreshold else { continue }
            
            // Calculate angle between segments
            let dot = (d1.x * d2.x + d1.y * d2.y)
            let cross = (d1.x * d2.y - d1.y * d2.x)
            let angle = abs(atan2(cross, dot))
            
            // If angle is sharp enough, mark as corner
            if angle > angleThreshold {
                cornerIndices.append(i)
            }
        }
        
        // Add the last point
        cornerIndices.append(points.count - 1)
        
        // Create substrokes between corners
        var newSubstrokes: [Substroke] = []
        for i in 0..<cornerIndices.count-1 {
            let start = cornerIndices[i]
            let end = cornerIndices[i+1]
            let substrokePoints = Array(points[start...end])
            newSubstrokes.append(Substroke(points: substrokePoints, startIndex: start, endIndex: end))
        }
        
        self.substrokes = newSubstrokes
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
        
        // Update substrokes if we have enough points
        if points.count >= 3 {
            detectSubstrokes()
        }
    }
}

/// Represents a complete character composed of multiple strokes
struct CharacterDrawing: Identifiable, Equatable {
    let id: UUID
    var strokes: [Stroke]
    var startTime: TimeInterval
    var endTime: TimeInterval
    
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
}

/// A view model to manage the drawing state
@MainActor
class DrawingViewModel: ObservableObject {
    @Published private(set) var currentStroke: Stroke?
    @Published private(set) var currentCharacter: CharacterDrawing
    @Published private(set) var characters: [CharacterDrawing] = []
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
    func beginStroke(at location: CGPoint, force: CGFloat? = nil) {
        // If not in character mode, start a new character
        if !isInCharacterMode && !currentCharacter.strokes.isEmpty {
            characters.append(currentCharacter)
            currentCharacter = CharacterDrawing()
        }
        
        let point = StrokePoint(location: location, timestamp: Date().timeIntervalSince1970, force: force)
        currentStroke = Stroke(points: [point])
    }
    
    /// Call this when the touch moves
    func continueStroke(at location: CGPoint, force: CGFloat? = nil) {
        guard var stroke = currentStroke else { return }
        let point = StrokePoint(location: location, timestamp: Date().timeIntervalSince1970, force: force)
        stroke.addPoint(point)
        currentStroke = stroke
    }
    
    /// Call this when the touch ends
    func endStroke() {
        guard let stroke = currentStroke, !stroke.points.isEmpty else {
            currentStroke = nil
            return
        }
        
        var finalStroke = stroke
        // Ensure we have at least 2 points for a valid stroke
        if finalStroke.points.count == 1 {
            let point = finalStroke.points[0]
            finalStroke.addPoint(StrokePoint(location: CGPoint(x: point.location.x + 0.1, y: point.location.y + 0.1), 
                                           timestamp: point.timestamp + 0.01, 
                                           force: point.force))
        }
        
        currentCharacter.addStroke(finalStroke)
        currentStroke = nil
    }
    
    /// Toggle character mode on/off
    func toggleCharacterMode() {
        isInCharacterMode.toggle()
    }
    
    /// Complete the current character and start a new one
    func completeCurrentCharacter() {
        guard !currentCharacter.strokes.isEmpty else { return }
        characters.append(currentCharacter)
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
    }
}
