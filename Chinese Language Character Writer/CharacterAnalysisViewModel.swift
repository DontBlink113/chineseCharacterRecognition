import Foundation
import Combine

class CharacterAnalysisViewModel: ObservableObject {
    @Published var characters: [String] = []
    @Published var analysisResults: [CharacterAnalysis] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isServerAvailable = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        checkServerStatus()
    }
    
    func analyzeCharacters() {
        guard !characters.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        NetworkManager.shared.analyzeCharacters(characters) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                switch result {
                case .success(let analysis):
                    self?.analysisResults = analysis
                case .failure(let error):
                    self?.handleError(error)
                }
            }
        }
    }
    
    func checkServerStatus() {
        NetworkManager.shared.checkServerHealth { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let isAvailable):
                    self?.isServerAvailable = isAvailable
                case .failure:
                    self?.isServerAvailable = false
                }
            }
        }
    }
    
    private func handleError(_ error: NetworkError) {
        switch error {
        case .invalidURL:
            errorMessage = "Invalid server URL. Please check your configuration."
        case .noData:
            errorMessage = "No data received from the server."
        case .decodingError:
            errorMessage = "Error processing the server response."
        case .serverError(let message):
            errorMessage = "Server error: \(message)"
        }
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
