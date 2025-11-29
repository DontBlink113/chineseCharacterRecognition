import Foundation
import Combine

class CharacterAnalysisViewModel: ObservableObject {
    @Published var characters: [String] = []
    @Published var analysisResults: [Character] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let characterAnalyzer = CharacterAnalyzer.shared
    
    func analyzeCharacters() {
        guard !characters.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        // Process characters locally
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let results = self.characterAnalyzer.analyzeMultiple(characters: self.characters)
            
            DispatchQueue.main.async {
                self.isLoading = false
                self.analysisResults = results
                
                if results.isEmpty {
                    self.errorMessage = "No character data found"
                }
            }
        }
    }
    
    func clearResults() {
        characters = []
        analysisResults = []
        errorMessage = nil
    }
    
    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
    }
    
    // Add a new character to analyze
    func addCharacter(_ character: String) {
        guard !character.isEmpty, !characters.contains(character) else { return }
        characters.append(character)
    }
    
    // Remove a character from analysis
    func removeCharacter(at index: Int) {
        guard index < characters.count else { return }
        characters.remove(at: index)
    }
    
    // Clear all characters and results
    func clearAll() {
        characters.removeAll()
        analysisResults.removeAll()
        errorMessage = nil
    }
}
