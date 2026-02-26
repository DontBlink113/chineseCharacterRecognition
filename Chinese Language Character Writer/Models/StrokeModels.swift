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
    let pressure: CGFloat
    let speed: CGFloat
    
    init(location: CGPoint, timestamp: TimeInterval = Date().timeIntervalSince1970, pressure: CGFloat = 1.0, speed: CGFloat = 0.0) {
        self.location = location
        self.timestamp = timestamp
        self.pressure = pressure
        self.speed = speed
    }
}

/// Represents a single stroke from touch down to lift
struct Stroke: Identifiable, Equatable {
    let id: UUID
    var points: [StrokePoint] // Filtered points for analysis
    var displayPoints: [StrokePoint] // All points for smooth rendering
    var startTime: TimeInterval
    var endTime: TimeInterval
    
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
    
    init(id: UUID = UUID(), points: [StrokePoint] = [], displayPoints: [StrokePoint]? = nil) {
        self.id = id
        self.points = points
        self.displayPoints = displayPoints ?? points
        self.startTime = points.first?.timestamp ?? Date().timeIntervalSince1970
        self.endTime = points.last?.timestamp ?? Date().timeIntervalSince1970
    }
    
    /// Adds a new point to the stroke (for analysis)
    mutating func addPoint(_ point: StrokePoint) {
        points.append(point)
        endTime = point.timestamp
        if points.count == 1 {
            startTime = point.timestamp
        }
    }
    
    /// Adds a new display point to the stroke (for rendering)
    mutating func addDisplayPoint(_ point: StrokePoint) {
        displayPoints.append(point)
    }
    
    // No substroke detection during drawing - deferred to endStroke()
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
    
    /// Average stroke speed in points per second
    var averageStrokeSpeed: Double {
        guard !strokes.isEmpty else { return 0 }
        let totalDuration = duration > 0 ? duration : 0.1 // Avoid division by zero
        return Double(totalPoints) / totalDuration
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

}

/// A view model to manage the drawing state
@MainActor
class DrawingViewModel: ObservableObject {
    @Published private(set) var currentStroke: Stroke?
    @Published private(set) var currentCharacter: CharacterDrawing
    @Published private(set) var characters: [CharacterDrawing] = []
    
    // Point sampling settings
    private let minimumTimeInterval: TimeInterval = 0.05 // 50ms
    private let minimumDistanceSquared: CGFloat = 36.0 // 6 points squared (for efficiency)
    private var lastPointTime: TimeInterval = 0
    private var lastPoint: CGPoint?
    
    @Published var isInCharacterMode: Bool = true {
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
        
        // Always add to display points for smooth rendering
        let lastDisplay = stroke.displayPoints.last
        let dtDisplay = max(1e-3, now - (lastDisplay?.timestamp ?? now))
        let dxDisplay = location.x - (lastDisplay?.location.x ?? location.x)
        let dyDisplay = location.y - (lastDisplay?.location.y ?? location.y)
        let rawSpeedDisplay = sqrt(dxDisplay * dxDisplay + dyDisplay * dyDisplay) / CGFloat(dtDisplay)
        let smoothedSpeedDisplay = lastDisplay != nil ? (0.6 * (lastDisplay!.speed) + 0.4 * rawSpeedDisplay) : 0
        let displayPoint = StrokePoint(location: location, timestamp: now, pressure: 1.0, speed: smoothedSpeedDisplay)
        stroke.addDisplayPoint(displayPoint)
        
        // Check if enough time has passed and point is far enough from last point for analysis
        if timeSinceLastPoint >= minimumTimeInterval,
           let lastLocation = lastPoint,
           distanceSquared(from: lastLocation, to: location) >= minimumDistanceSquared {
            
            lastPointTime = now
            lastPoint = location
            
            let lastAnalysis = stroke.points.last
            let dt = max(1e-3, now - (lastAnalysis?.timestamp ?? now))
            let dx = location.x - (lastAnalysis?.location.x ?? location.x)
            let dy = location.y - (lastAnalysis?.location.y ?? location.y)
            let rawSpeed = sqrt(dx * dx + dy * dy) / CGFloat(dt)
            let smoothedSpeed = lastAnalysis != nil ? (0.6 * (lastAnalysis!.speed) + 0.4 * rawSpeed) : 0
            let point = StrokePoint(location: location, timestamp: now, pressure: 1.0, speed: smoothedSpeed)
            stroke.addPoint(point)
        }
        
        currentStroke = stroke
    }
    
    /// Calculate squared distance between two points (more efficient than calculating actual distance)
    private func distanceSquared(from point1: CGPoint, to point2: CGPoint) -> CGFloat {
        let dx = point2.x - point1.x
        let dy = point2.y - point1.y
        return dx * dx + dy * dy
    }

    /// Call this when a new touch begins with pressure
    func beginStrokeWithPressure(at location: CGPoint, pressure: CGFloat) {
        if !isInCharacterMode && !currentCharacter.strokes.isEmpty {
            characters.append(currentCharacter)
            currentCharacter = CharacterDrawing()
        }
        let now = Date().timeIntervalSince1970
        lastPointTime = now
        lastPoint = location
        let p = max(0.0, min(1.0, pressure))
        let point = StrokePoint(location: location, timestamp: now, pressure: p, speed: 0)
        // Create stroke with unique ID and initial display point
        currentStroke = Stroke(id: UUID(), points: [point], displayPoints: [point])
    }

    /// Call this when the touch moves with pressure
    func continueStrokeWithPressure(at location: CGPoint, pressure: CGFloat) {
        guard var stroke = currentStroke else { return }
        let now = Date().timeIntervalSince1970
        let timeSinceLastPoint = now - lastPointTime
        let p = max(0.0, min(1.0, pressure))
        let lastDisplay = stroke.displayPoints.last
        let dtDisplay = max(1e-3, now - (lastDisplay?.timestamp ?? now))
        let dxDisplay = location.x - (lastDisplay?.location.x ?? location.x)
        let dyDisplay = location.y - (lastDisplay?.location.y ?? location.y)
        let rawSpeedDisplay = sqrt(dxDisplay * dxDisplay + dyDisplay * dyDisplay) / CGFloat(dtDisplay)
        let smoothedSpeedDisplay = lastDisplay != nil ? (0.6 * (lastDisplay!.speed) + 0.4 * rawSpeedDisplay) : 0
        let displayPoint = StrokePoint(location: location, timestamp: now, pressure: p, speed: smoothedSpeedDisplay)
        stroke.addDisplayPoint(displayPoint)
        if timeSinceLastPoint >= minimumTimeInterval,
           let lastLocation = lastPoint,
           distanceSquared(from: lastLocation, to: location) >= minimumDistanceSquared {
            lastPointTime = now
            lastPoint = location
            let lastAnalysis = stroke.points.last
            let dt = max(1e-3, now - (lastAnalysis?.timestamp ?? now))
            let dx = location.x - (lastAnalysis?.location.x ?? location.x)
            let dy = location.y - (lastAnalysis?.location.y ?? location.y)
            let rawSpeed = sqrt(dx * dx + dy * dy) / CGFloat(dt)
            let smoothedSpeed = lastAnalysis != nil ? (0.6 * (lastAnalysis!.speed) + 0.4 * rawSpeed) : 0
            let point = StrokePoint(location: location, timestamp: now, pressure: p, speed: smoothedSpeed)
            stroke.addPoint(point)
        }
        currentStroke = stroke
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
        currentCharacter = CharacterDrawing() // Create new instance to trigger @Published update
        characters.removeAll()
        currentStroke = nil
    }

    
}
