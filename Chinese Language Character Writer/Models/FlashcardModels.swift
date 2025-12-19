import Foundation

public struct FlashcardItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public var hanzi: String
    public var definition: String

    public init(id: UUID = UUID(), hanzi: String, definition: String = "") {
        self.id = id
        self.hanzi = hanzi
        self.definition = definition
    }
}
