import Foundation
import CoreData

class CoreDataManager: ObservableObject {
    static let shared = CoreDataManager()
    
    let container: NSPersistentContainer
    
    private init() {
        container = NSPersistentContainer(name: "FlashcardModel")
        
        // Create the model programmatically
        let model = NSManagedObjectModel()
        
        // CharacterReviewData Entity
        let characterEntity = NSEntityDescription()
        characterEntity.name = "CharacterReviewData"
        characterEntity.managedObjectClassName = NSStringFromClass(CharacterReviewData.self)
        
        // Attributes
        var properties: [NSAttributeDescription] = []
        
        let idAttr = NSAttributeDescription()
        idAttr.name = "id"
        idAttr.attributeType = .UUIDAttributeType
        idAttr.isOptional = false
        properties.append(idAttr)
        
        let hanziAttr = NSAttributeDescription()
        hanziAttr.name = "hanzi"
        hanziAttr.attributeType = .stringAttributeType
        hanziAttr.isOptional = false
        properties.append(hanziAttr)
        
        let definitionAttr = NSAttributeDescription()
        definitionAttr.name = "definition"
        definitionAttr.attributeType = .stringAttributeType
        definitionAttr.isOptional = false
        properties.append(definitionAttr)
        
        let setIdAttr = NSAttributeDescription()
        setIdAttr.name = "setId"
        setIdAttr.attributeType = .UUIDAttributeType
        setIdAttr.isOptional = false
        properties.append(setIdAttr)
        
        // PromptToChar direction
        let ptcStabilityAttr = NSAttributeDescription()
        ptcStabilityAttr.name = "promptToCharStability"
        ptcStabilityAttr.attributeType = .doubleAttributeType
        ptcStabilityAttr.defaultValue = 0.0
        properties.append(ptcStabilityAttr)
        
        let ptcDifficultyAttr = NSAttributeDescription()
        ptcDifficultyAttr.name = "promptToCharDifficulty"
        ptcDifficultyAttr.attributeType = .doubleAttributeType
        ptcDifficultyAttr.defaultValue = 0.0
        properties.append(ptcDifficultyAttr)
        
        let ptcLastReviewAttr = NSAttributeDescription()
        ptcLastReviewAttr.name = "promptToCharLastReview"
        ptcLastReviewAttr.attributeType = .dateAttributeType
        ptcLastReviewAttr.isOptional = true
        properties.append(ptcLastReviewAttr)
        
        let ptcDueAttr = NSAttributeDescription()
        ptcDueAttr.name = "promptToCharDue"
        ptcDueAttr.attributeType = .dateAttributeType
        ptcDueAttr.defaultValue = Date()
        properties.append(ptcDueAttr)
        
        let ptcStateAttr = NSAttributeDescription()
        ptcStateAttr.name = "promptToCharState"
        ptcStateAttr.attributeType = .integer16AttributeType
        ptcStateAttr.defaultValue = 0
        properties.append(ptcStateAttr)
        
        let ptcHistoryAttr = NSAttributeDescription()
        ptcHistoryAttr.name = "promptToCharHistory"
        ptcHistoryAttr.attributeType = .binaryDataAttributeType
        ptcHistoryAttr.isOptional = true
        properties.append(ptcHistoryAttr)
        
        // CharToPrompt direction
        let ctpStabilityAttr = NSAttributeDescription()
        ctpStabilityAttr.name = "charToPromptStability"
        ctpStabilityAttr.attributeType = .doubleAttributeType
        ctpStabilityAttr.defaultValue = 0.0
        properties.append(ctpStabilityAttr)
        
        let ctpDifficultyAttr = NSAttributeDescription()
        ctpDifficultyAttr.name = "charToPromptDifficulty"
        ctpDifficultyAttr.attributeType = .doubleAttributeType
        ctpDifficultyAttr.defaultValue = 0.0
        properties.append(ctpDifficultyAttr)
        
        let ctpLastReviewAttr = NSAttributeDescription()
        ctpLastReviewAttr.name = "charToPromptLastReview"
        ctpLastReviewAttr.attributeType = .dateAttributeType
        ctpLastReviewAttr.isOptional = true
        properties.append(ctpLastReviewAttr)
        
        let ctpDueAttr = NSAttributeDescription()
        ctpDueAttr.name = "charToPromptDue"
        ctpDueAttr.attributeType = .dateAttributeType
        ctpDueAttr.defaultValue = Date()
        properties.append(ctpDueAttr)
        
        let ctpStateAttr = NSAttributeDescription()
        ctpStateAttr.name = "charToPromptState"
        ctpStateAttr.attributeType = .integer16AttributeType
        ctpStateAttr.defaultValue = 0
        properties.append(ctpStateAttr)
        
        let ctpHistoryAttr = NSAttributeDescription()
        ctpHistoryAttr.name = "charToPromptHistory"
        ctpHistoryAttr.attributeType = .binaryDataAttributeType
        ctpHistoryAttr.isOptional = true
        properties.append(ctpHistoryAttr)
        
        characterEntity.properties = properties
        model.entities = [characterEntity]
        
        // Use the programmatic model
        container.persistentStoreDescriptions.first?.url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("FlashcardData.sqlite")
        
        let description = NSPersistentStoreDescription()
        description.type = NSSQLiteStoreType
        container.persistentStoreDescriptions = [description]
        
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Core Data failed to load: \(error.localizedDescription)")
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    // MARK: - CRUD Operations
    
    func saveContext() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Error saving context: \(error)")
            }
        }
    }
    
    func createCharacter(id: UUID, hanzi: String, definition: String, setId: UUID) -> CharacterReviewData {
        let context = container.viewContext
        let character = CharacterReviewData(context: context)
        character.id = id
        character.hanzi = hanzi
        character.definition = definition
        character.setId = setId
        
        // Initialize with default FSRS values
        character.promptToCharStability = 0.0
        character.promptToCharDifficulty = 0.0
        character.promptToCharDue = Date()
        character.promptToCharState = 0 // .new
        
        character.charToPromptStability = 0.0
        character.charToPromptDifficulty = 0.0
        character.charToPromptDue = Date()
        character.charToPromptState = 0 // .new
        
        saveContext()
        return character
    }
    
    func fetchAllCharacters() -> [CharacterReviewData] {
        let request: NSFetchRequest<CharacterReviewData> = CharacterReviewData.fetchRequest()
        do {
            return try container.viewContext.fetch(request)
        } catch {
            print("Error fetching characters: \(error)")
            return []
        }
    }
    
    func fetchCharacter(byId id: UUID) -> CharacterReviewData? {
        let request: NSFetchRequest<CharacterReviewData> = CharacterReviewData.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        
        do {
            return try container.viewContext.fetch(request).first
        } catch {
            print("Error fetching character: \(error)")
            return nil
        }
    }
    
    func fetchCharacters(forSetId setId: UUID) -> [CharacterReviewData] {
        let request: NSFetchRequest<CharacterReviewData> = CharacterReviewData.fetchRequest()
        request.predicate = NSPredicate(format: "setId == %@", setId as CVarArg)
        
        do {
            return try container.viewContext.fetch(request)
        } catch {
            print("Error fetching characters for set: \(error)")
            return []
        }
    }
    
    func deleteCharacter(_ character: CharacterReviewData) {
        container.viewContext.delete(character)
        saveContext()
    }
    
    func deleteAllCharacters(forSetId setId: UUID) {
        let characters = fetchCharacters(forSetId: setId)
        for character in characters {
            container.viewContext.delete(character)
        }
        saveContext()
    }
}

// MARK: - NSManagedObject Subclass

@objc(CharacterReviewData)
public class CharacterReviewData: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var hanzi: String
    @NSManaged public var definition: String
    @NSManaged public var setId: UUID
    
    // PromptToChar (Definition → Character)
    @NSManaged public var promptToCharStability: Double
    @NSManaged public var promptToCharDifficulty: Double
    @NSManaged public var promptToCharLastReview: Date?
    @NSManaged public var promptToCharDue: Date
    @NSManaged public var promptToCharState: Int16
    @NSManaged public var promptToCharHistory: Data?
    
    // CharToPrompt (Character → Definition)
    @NSManaged public var charToPromptStability: Double
    @NSManaged public var charToPromptDifficulty: Double
    @NSManaged public var charToPromptLastReview: Date?
    @NSManaged public var charToPromptDue: Date
    @NSManaged public var charToPromptState: Int16
    @NSManaged public var charToPromptHistory: Data?
}

extension CharacterReviewData {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CharacterReviewData> {
        return NSFetchRequest<CharacterReviewData>(entityName: "CharacterReviewData")
    }
    
    // Convert to FlashcardItem
    func toFlashcardItem() -> FlashcardItem {
        let promptToChar = FSRSData(
            due: promptToCharDue,
            state: FSRSState(rawValue: Int(promptToCharState)) ?? .new,
            lastReview: promptToCharLastReview,
            stability: promptToCharStability,
            difficulty: promptToCharDifficulty,
            scheduledDays: 0,
            learningSteps: 0,
            reps: 0,
            lapses: 0,
            reviewHistory: decodeHistory(promptToCharHistory) ?? []
        )
        
        let charToPrompt = FSRSData(
            due: charToPromptDue,
            state: FSRSState(rawValue: Int(charToPromptState)) ?? .new,
            lastReview: charToPromptLastReview,
            stability: charToPromptStability,
            difficulty: charToPromptDifficulty,
            scheduledDays: 0,
            learningSteps: 0,
            reps: 0,
            lapses: 0,
            reviewHistory: decodeHistory(charToPromptHistory) ?? []
        )
        
        return FlashcardItem(
            id: id,
            hanzi: hanzi,
            definition: definition,
            promptToChar: promptToChar,
            charToPrompt: charToPrompt
        )
    }
    
    // Update from FlashcardItem
    func update(from item: FlashcardItem) {
        hanzi = item.hanzi
        definition = item.definition
        
        // PromptToChar
        promptToCharStability = item.promptToChar.stability
        promptToCharDifficulty = item.promptToChar.difficulty
        promptToCharLastReview = item.promptToChar.lastReview
        promptToCharDue = item.promptToChar.due
        promptToCharState = Int16(item.promptToChar.state.rawValue)
        promptToCharHistory = encodeHistory(item.promptToChar.reviewHistory)
        
        // CharToPrompt
        charToPromptStability = item.charToPrompt.stability
        charToPromptDifficulty = item.charToPrompt.difficulty
        charToPromptLastReview = item.charToPrompt.lastReview
        charToPromptDue = item.charToPrompt.due
        charToPromptState = Int16(item.charToPrompt.state.rawValue)
        charToPromptHistory = encodeHistory(item.charToPrompt.reviewHistory)
    }
    
    private func encodeHistory(_ history: [FSRSReviewLog]) -> Data? {
        try? JSONEncoder().encode(history)
    }
    
    private func decodeHistory(_ data: Data?) -> [FSRSReviewLog]? {
        guard let data = data else { return nil }
        return try? JSONDecoder().decode([FSRSReviewLog].self, from: data)
    }
}
