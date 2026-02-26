import SwiftUI

struct CharacterSetsView: View {
    @EnvironmentObject var store: LearningSetsStore
    @State private var name: String = ""
    @State private var characters: String = ""
    @State private var showAddSetError: Bool = false
    @State private var addSetErrorMessage: String = ""

    var body: some View {
        ZStack {
            Color("Secondary100")
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Title
                    Text("Character Sets")
                        .font(.system(size: 40)).bold()
                        .foregroundColor(Color("Primary900"))
                        .padding(.top, 20)
                    
                    // Create Flashcard Set Button
                    NavigationLink(destination: FlashcardSetCreationView()) {
                        HStack {
                            Image(systemName: "plus.rectangle.on.rectangle")
                                .font(.title3)
                            Text("Create Flashcard Set")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(Color("Secondary100"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color("Primary600"))
                        .cornerRadius(12)
                    }
                    // Saved Sets Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Saved Sets")
                            .font(.title2).bold()
                            .foregroundColor(Color("Primary900"))
                            .padding(.horizontal, 20)
                        
                        if store.sets.isEmpty {
                            Text("No sets yet. Add your first set above!")
                                .foregroundColor(Color("Neutral700"))
                                .padding(20)
                                .frame(maxWidth: .infinity)
                        } else {
                            ForEach(store.sets) { set in
                                VStack(spacing: 0) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 8) {
                                                Text(set.name)
                                                    .font(.headline)
                                                    .foregroundColor(Color("Primary900"))
                                                
                                                // Definition status indicator
                                                if set.hasDefinitions {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .font(.caption)
                                                        .foregroundColor(.green)
                                                } else {
                                                    Image(systemName: "exclamationmark.circle")
                                                        .font(.caption)
                                                        .foregroundColor(Color("Accent200"))
                                                }
                                            }
                                            Text("\(extractHanzi(from: set.characters).count) characters")
                                                .font(.caption)
                                                .foregroundColor(Color("Neutral700"))
                                        }
                                        Spacer()
                                        if store.activeSetId == set.id {
                                            Text("Active")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(Color("Primary700"))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color("Primary700").opacity(0.2))
                                                .cornerRadius(12)
                                        } else {
                                            Button(action: { store.setActive(set) }) {
                                                Text("Use")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(Color("Primary700"))
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 6)
                                                    .background(Color.white)
                                                    .cornerRadius(12)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .stroke(Color("Primary700"), lineWidth: 1.5)
                                                    )
                                            }
                                        }
                                    }
                                    .padding(16)
                                    
                                    // Edit Character List button
                                    NavigationLink(destination: AddDefinitionsView(setId: set.id)) {
                                        HStack {
                                            Image(systemName: "pencil")
                                            Text("Edit List")
                                        }
                                        .font(.subheadline)
                                        .foregroundColor(Color("Primary700"))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color.white)
                                        .cornerRadius(8)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 12)
                                }
                                .background(Color.white.opacity(0.7))
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                            }
                            .onDelete(perform: store.remove)
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.vertical, 20)
                    .background(Color.white.opacity(0.5))
                    .cornerRadius(16)
                    .padding(.horizontal, 24)
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .alert(isPresented: $showAddSetError) {
            Alert(
                title: Text("Invalid Characters"),
                message: Text(addSetErrorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CharacterSetsView_Previews: PreviewProvider {
    static var previews: some View {
        CharacterSetsView().environmentObject(LearningSetsStore())
    }
}

// Extracts unique Chinese characters from input (CJK ranges)
private func extractHanzi(from text: String) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for scalar in text.unicodeScalars {
        let v = scalar.value
        if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v) {
            let s = String(scalar)
            if !seen.contains(s) {
                seen.insert(s)
                result.append(s)
            }
        }
    }
    return result
}
