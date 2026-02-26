import Foundation
import FSRS

class FSRSService: ObservableObject {
    static let shared = FSRSService()
    
    private var fsrs: FSRS
    private let coreDataManager = CoreDataManager.shared
    
    @Published var allCards: [FlashcardItem] = []
    
    private init() {
        // Initialize FSRS with default parameters
        self.fsrs = FSRS()
        
        // Load all characters from Core Data on init
        loadAllCharacters()
    }
    
    // MARK: - Loading Data
    
    func loadAllCharacters() {
        let coreDataCharacters = coreDataManager.fetchAllCharacters()
        allCards = coreDataCharacters.map { $0.toFlashcardItem() }
    }
    
    func loadCharacters(forSetId setId: UUID) -> [FlashcardItem] {
        let coreDataCharacters = coreDataManager.fetchCharacters(forSetId: setId)
        return coreDataCharacters.map { $0.toFlashcardItem() }
    }
    
    // MARK: - Creating New Characters
    
    func addCharacter(id: UUID = UUID(), hanzi: String, definition: String, setId: UUID) -> FlashcardItem {
        let coreDataChar = coreDataManager.createCharacter(
            id: id,
            hanzi: hanzi,
            definition: definition,
            setId: setId
        )
        
        let flashcardItem = coreDataChar.toFlashcardItem()
        allCards.append(flashcardItem)
        
        return flashcardItem
    }
    
    func addCharacters(_ characters: [(hanzi: String, definition: String)], toSetId setId: UUID) -> [FlashcardItem] {
        var newItems: [FlashcardItem] = []
        
        for char in characters {
            let item = addCharacter(hanzi: char.hanzi, definition: char.definition, setId: setId)
            newItems.append(item)
        }
        
        return newItems
    }
    
    // MARK: - Review Logic
    
    /// Review a card in the promptToChar direction (Definition → Character)
    func reviewPromptToChar(cardId: UUID, rating: DifficultyRating) {
        guard let coreDataChar = coreDataManager.fetchCharacter(byId: cardId) else { return }
        
        // Convert DifficultyRating to FSRS Rating (1-4)
        let fsrsRating = convertToFSRSRating(rating)
        
        // Get current card state
        var card = createFSRSCard(from: coreDataChar, direction: .promptToChar)
        
        // Get current time
        let now = Date()
        
        // Perform review using FSRS
        let schedulingCards = fsrs.repeat(card: card, now: now)
        
        // Get the updated card based on rating
        let updatedCard: Card
        switch fsrsRating {
        case .again:
            updatedCard = schedulingCards.again.card
        case .hard:
            updatedCard = schedulingCards.hard.card
        case .good:
            updatedCard = schedulingCards.good.card
        case .easy:
            updatedCard = schedulingCards.easy.card
        }
        
        // Update Core Data with new FSRS values
        coreDataChar.promptToCharStability = updatedCard.stability
        coreDataChar.promptToCharDifficulty = updatedCard.difficulty
        coreDataChar.promptToCharLastReview = now
        coreDataChar.promptToCharDue = updatedCard.due
        coreDataChar.promptToCharState = Int16(updatedCard.state.rawValue)
        
        // Add to review history
        let reviewLog = FSRSReviewLog(
            rating: fsrsRating.rawValue,
            reviewDate: now,
            scheduledDays: Int(updatedCard.scheduledDays),
            elapsedDays: Int(updatedCard.elapsedDays),
            state: FSRSState(rawValue: updatedCard.state.rawValue) ?? .new
        )
        
        var history = coreDataChar.toFlashcardItem().promptToChar.reviewHistory
        history.append(reviewLog)
        coreDataChar.promptToCharHistory = try? JSONEncoder().encode(history)
        
        coreDataManager.saveContext()
        
        // Reload all cards to update in-memory state
        loadAllCharacters()
    }
    
    /// Review a card in the charToPrompt direction (Character → Definition)
    func reviewCharToPrompt(cardId: UUID, rating: DifficultyRating) {
        guard let coreDataChar = coreDataManager.fetchCharacter(byId: cardId) else { return }
        
        let fsrsRating = convertToFSRSRating(rating)
        var card = createFSRSCard(from: coreDataChar, direction: .charToPrompt)
        let now = Date()
        
        let schedulingCards = fsrs.repeat(card: card, now: now)
        
        let updatedCard: Card
        switch fsrsRating {
        case .again:
            updatedCard = schedulingCards.again.card
        case .hard:
            updatedCard = schedulingCards.hard.card
        case .good:
            updatedCard = schedulingCards.good.card
        case .easy:
            updatedCard = schedulingCards.easy.card
        }
        
        coreDataChar.charToPromptStability = updatedCard.stability
        coreDataChar.charToPromptDifficulty = updatedCard.difficulty
        coreDataChar.charToPromptLastReview = now
        coreDataChar.charToPromptDue = updatedCard.due
        coreDataChar.charToPromptState = Int16(updatedCard.state.rawValue)
        
        let reviewLog = FSRSReviewLog(
            rating: fsrsRating.rawValue,
            reviewDate: now,
            scheduledDays: Int(updatedCard.scheduledDays),
            elapsedDays: Int(updatedCard.elapsedDays),
            state: FSRSState(rawValue: updatedCard.state.rawValue) ?? .new
        )
        
        var history = coreDataChar.toFlashcardItem().charToPrompt.reviewHistory
        history.append(reviewLog)
        coreDataChar.charToPromptHistory = try? JSONEncoder().encode(history)
        
        coreDataManager.saveContext()
        loadAllCharacters()
    }
    
    // MARK: - Due Cards & Recall Rating
    
    /// Get recall probability from FSRS Card's built-in retrievability property
    func calculateRecallRating(for card: FlashcardItem, direction: ReviewDirection) -> Double {
        guard let coreDataChar = coreDataManager.fetchCharacter(byId: card.id) else {
            return 1.0 // Default for cards not found
        }
        
        let fsrsCard = createFSRSCard(from: coreDataChar, direction: direction)
        return fsrsCard.retrievability
    }
    
    func getDueCards(direction: ReviewDirection = .promptToChar) -> [FlashcardItem] {
        let now = Date()
        
        return allCards.filter { card in
            switch direction {
            case .promptToChar:
                return card.promptToChar.due <= now
            case .charToPrompt:
                return card.charToPrompt.due <= now
            }
        }
    }
    
    func getNewCards(direction: ReviewDirection = .promptToChar) -> [FlashcardItem] {
        return allCards.filter { card in
            switch direction {
            case .promptToChar:
                return card.promptToChar.state == .new
            case .charToPrompt:
                return card.charToPrompt.state == .new
            }
        }
    }
    
    // MARK: - Spaced Repetition Ordering
    
    /// Get cards ordered by spaced repetition priority:
    /// 1. Active cards not yet reviewed (state != .new && lastReview == nil)
    /// 2. Due cards with recall < 90%, sorted by lowest recall first
    /// 3. All other cards, sorted by lowest recall first
    func getCardsForSpacedRepetition(setIds: Set<UUID>, direction: ReviewDirection) -> [FlashcardItem] {
        // Filter cards by selected sets
        let cardsInSets = allCards.filter { card in
            guard let coreDataChar = coreDataManager.fetchCharacter(byId: card.id) else { return false }
            return setIds.contains(coreDataChar.setId)
        }
        
        let now = Date()
        var priority1: [FlashcardItem] = [] // Active but not reviewed
        var priority2: [(card: FlashcardItem, recall: Double)] = [] // Due with recall < 90%
        var priority3: [(card: FlashcardItem, recall: Double)] = [] // All others
        
        for card in cardsInSets {
            let data: FSRSData
            switch direction {
            case .promptToChar:
                data = card.promptToChar
            case .charToPrompt:
                data = card.charToPrompt
            }
            
            // Priority 1: Active but not yet reviewed
            if data.state != .new && data.lastReview == nil {
                priority1.append(card)
                continue
            }
            
            let recall = calculateRecallRating(for: card, direction: direction)
            
            // Priority 2: Due cards with recall < 90%
            if data.due <= now && recall < 0.9 {
                priority2.append((card, recall))
            } else {
                // Priority 3: Everything else
                priority3.append((card, recall))
            }
        }
        
        // Sort priority 2 and 3 by lowest recall first
        priority2.sort { $0.recall < $1.recall }
        priority3.sort { $0.recall < $1.recall }
        
        // Combine all priorities
        return priority1 + priority2.map { $0.card } + priority3.map { $0.card }
    }
    
    /// Get cards for normal sequential mode (original order)
    func getCardsSequential(setIds: Set<UUID>) -> [FlashcardItem] {
        return allCards.filter { card in
            guard let coreDataChar = coreDataManager.fetchCharacter(byId: card.id) else { return false }
            return setIds.contains(coreDataChar.setId)
        }
    }
    
    /// Get cards for normal shuffle mode (randomized)
    func getCardsShuffle(setIds: Set<UUID>) -> [FlashcardItem] {
        let sequential = getCardsSequential(setIds: setIds)
        return sequential.shuffled()
    }
    
    // MARK: - Helper Methods
    
    private func convertToFSRSRating(_ rating: DifficultyRating) -> Rating {
        switch rating {
        case .again:
            return .again
        case .hard:
            return .hard
        case .medium:
            return .good
        case .easy:
            return .easy
        }
    }
    
    private func createFSRSCard(from coreDataChar: CharacterReviewData, direction: ReviewDirection) -> Card {
        switch direction {
        case .promptToChar:
            return Card(
                due: coreDataChar.promptToCharDue,
                stability: coreDataChar.promptToCharStability,
                difficulty: coreDataChar.promptToCharDifficulty,
                elapsedDays: calculateElapsedDays(lastReview: coreDataChar.promptToCharLastReview),
                scheduledDays: calculateScheduledDays(due: coreDataChar.promptToCharDue, lastReview: coreDataChar.promptToCharLastReview),
                reps: 0,
                lapses: 0,
                state: State(rawValue: Int(coreDataChar.promptToCharState)) ?? .new,
                lastReview: coreDataChar.promptToCharLastReview
            )
        case .charToPrompt:
            return Card(
                due: coreDataChar.charToPromptDue,
                stability: coreDataChar.charToPromptStability,
                difficulty: coreDataChar.charToPromptDifficulty,
                elapsedDays: calculateElapsedDays(lastReview: coreDataChar.charToPromptLastReview),
                scheduledDays: calculateScheduledDays(due: coreDataChar.charToPromptDue, lastReview: coreDataChar.charToPromptLastReview),
                reps: 0,
                lapses: 0,
                state: State(rawValue: Int(coreDataChar.charToPromptState)) ?? .new,
                lastReview: coreDataChar.charToPromptLastReview
            )
        }
    }
    
    private func calculateElapsedDays(lastReview: Date?) -> UInt {
        guard let lastReview = lastReview else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: lastReview, to: Date()).day ?? 0
        return UInt(max(0, days))
    }
    
    private func calculateScheduledDays(due: Date, lastReview: Date?) -> UInt {
        guard let lastReview = lastReview else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: lastReview, to: due).day ?? 0
        return UInt(max(0, days))
    }
    
    // MARK: - Deletion
    
    func deleteCharacter(cardId: UUID) {
        guard let coreDataChar = coreDataManager.fetchCharacter(byId: cardId) else { return }
        coreDataManager.deleteCharacter(coreDataChar)
        allCards.removeAll { $0.id == cardId }
    }
    
    func deleteAllCharacters(forSetId setId: UUID) {
        coreDataManager.deleteAllCharacters(forSetId: setId)
        allCards.removeAll { card in
            // We need to check the setId - this requires fetching from Core Data
            guard let coreDataChar = coreDataManager.fetchCharacter(byId: card.id) else { return false }
            return coreDataChar.setId == setId
        }
    }
}

// MARK: - Review Direction

enum ReviewDirection {
    case promptToChar  // Definition → Character (for writer mode)
    case charToPrompt  // Character → Definition (for flip mode)
}
