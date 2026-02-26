import Foundation
import SwiftUI

// MARK: - FSRS Review History
public struct FSRSReviewLog: Codable, Equatable {
    public var rating: Int
    public var reviewDate: Date
    public var scheduledDays: Int
    public var elapsedDays: Int
    public var state: FSRSState
    
    public init(rating: Int, reviewDate: Date, scheduledDays: Int, elapsedDays: Int, state: FSRSState) {
        self.rating = rating
        self.reviewDate = reviewDate
        self.scheduledDays = scheduledDays
        self.elapsedDays = elapsedDays
        self.state = state
    }
}

// MARK: - FSRS State
public enum FSRSState: Int, Codable, Equatable {
    case new = 0         // Unseen card
    case learning = 1    // Currently learning
}

// MARK: - FSRS Data Model (FSRS-6 Compatible)
public struct FSRSData: Codable, Equatable {
    // Core FSRS-6 properties
    public var due: Date
    public var state: FSRSState
    public var lastReview: Date?
    public var stability: Double
    public var difficulty: Double
    public var scheduledDays: Int
    public var learningSteps: Int
    public var reps: Int
    public var lapses: Int
    
    // Review history for parameter optimization
    public var reviewHistory: [FSRSReviewLog]
    
    public init(
        due: Date = Date(),
        state: FSRSState = .new,
        lastReview: Date? = nil,
        stability: Double = 0,
        difficulty: Double = 0,
        scheduledDays: Int = 0,
        learningSteps: Int = 0,
        reps: Int = 0,
        lapses: Int = 0,
        reviewHistory: [FSRSReviewLog] = []
    ) {
        self.due = due
        self.state = state
        self.lastReview = lastReview
        self.stability = stability
        self.difficulty = difficulty
        self.scheduledDays = scheduledDays
        self.learningSteps = learningSteps
        self.reps = reps
        self.lapses = lapses
        self.reviewHistory = reviewHistory
    }
}

// MARK: - Flashcard Item Model
public struct FlashcardItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public var hanzi: String
    public var definition: String
    public var promptToChar: FSRSData
    public var charToPrompt: FSRSData
    
    public init(id: UUID = UUID(), hanzi: String, definition: String, promptToChar: FSRSData = FSRSData(), charToPrompt: FSRSData = FSRSData()) {
        self.id = id
        self.hanzi = hanzi
        self.definition = definition
        self.promptToChar = promptToChar
        self.charToPrompt = charToPrompt
    }
}

// MARK: - Practice Mode
public enum PracticeMode: String, CaseIterable, Codable {
    case flip = "Flip Cards"
    case draw = "Write Characters"
}

// MARK: - Difficulty Rating
public enum DifficultyRating: String, CaseIterable, Codable {
    case again = "Again"
    case hard = "Hard"
    case medium = "Medium"
    case easy = "Easy"
    
    public var color: Color {
        switch self {
        case .again: return .red
        case .hard: return .orange
        case .medium: return .yellow
        case .easy: return .green
        }
    }
    
    public var icon: String {
        switch self {
        case .again: return "arrow.counterclockwise.circle.fill"
        case .hard: return "exclamationmark.circle.fill"
        case .medium: return "minus.circle.fill"
        case .easy: return "checkmark.circle.fill"
        }
    }
}
