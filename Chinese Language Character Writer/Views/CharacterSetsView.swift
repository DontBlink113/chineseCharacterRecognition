import SwiftUI

struct CharacterSetsView: View {
    @EnvironmentObject var store: LearningSetsStore
    @State private var name: String = ""
    @State private var characters: String = ""

    var body: some View {
        ZStack {
            Color(red: 0.68, green: 0.85, blue: 0.9)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Title
                    Text("Learning Sets")
                        .font(.system(size: 40)).bold()
                        .foregroundColor(Color("Blue 900"))
                        .padding(.top, 20)
                    
                    // Add New Set Card
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Add New Set")
                            .font(.title2).bold()
                            .foregroundColor(Color("Blue 900"))
                        
                        TextField("Set Name", text: $name)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.white.opacity(0.9))
                            .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Characters")
                                .font(.subheadline)
                                .foregroundColor(Color("Blue 900"))
                            TextEditor(text: $characters)
                                .frame(minHeight: 120)
                                .padding(8)
                                .background(Color.white.opacity(0.9))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color("Blue 700").opacity(0.3), lineWidth: 1)
                                )
                        }
                        
                        Button(action: {
                            guard !name.isEmpty && !characters.isEmpty else { return }
                            store.add(name: name, characters: characters)
                            name = ""
                            characters = ""
                        }) {
                            Text("Add Set")
                                .font(.headline)
                                .foregroundColor(Color("Sand 100"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color("Blue 700"))
                                .cornerRadius(10)
                                .shadow(color: Color("Blue 700").opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .disabled(name.isEmpty || characters.isEmpty)
                        .opacity(name.isEmpty || characters.isEmpty ? 0.6 : 1.0)
                    }
                    .padding(20)
                    .background(Color.white.opacity(0.7))
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
                    .padding(.horizontal, 24)
                    
                    // Saved Sets Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Saved Sets")
                            .font(.title2).bold()
                            .foregroundColor(Color("Blue 900"))
                            .padding(.horizontal, 20)
                        
                        if store.sets.isEmpty {
                            Text("No sets yet. Add your first set above!")
                                .foregroundColor(Color("Neutral 700"))
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
                                                    .foregroundColor(Color("Blue 900"))
                                                
                                                // Definition status indicator
                                                if set.hasDefinitions {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .font(.caption)
                                                        .foregroundColor(.green)
                                                } else {
                                                    Image(systemName: "exclamationmark.circle")
                                                        .font(.caption)
                                                        .foregroundColor(Color("Orange 200"))
                                                }
                                            }
                                            Text("\(extractHanzi(from: set.characters).count) characters")
                                                .font(.caption)
                                                .foregroundColor(Color("Neutral 700"))
                                        }
                                        Spacer()
                                        if store.activeSetId == set.id {
                                            Text("Active")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(Color("Blue 700"))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color("Blue 700").opacity(0.2))
                                                .cornerRadius(12)
                                        } else {
                                            Button(action: { store.setActive(set) }) {
                                                Text("Use")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(Color("Blue 700"))
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 6)
                                                    .background(Color.white)
                                                    .cornerRadius(12)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .stroke(Color("Blue 700"), lineWidth: 1.5)
                                                    )
                                            }
                                        }
                                    }
                                    .padding(16)
                                    
                                    // Add Definitions button
                                    NavigationLink(destination: AddDefinitionsView(setId: set.id)) {
                                        HStack {
                                            Image(systemName: set.hasDefinitions ? "pencil" : "plus.circle")
                                            Text(set.hasDefinitions ? "Edit Definitions" : "Add Definitions")
                                        }
                                        .font(.subheadline)
                                        .foregroundColor(Color("Blue 700"))
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
