import SwiftUI

struct CharacterSetsView: View {
    @EnvironmentObject var store: LearningSetsStore
    @State private var name: String = ""
    @State private var characters: String = ""
    @State private var error: String? = nil

    var body: some View {
        Form {
                NavigationLink(destination: EditLearningSetView()) {
                    Text("New Flashcard Set")
                        .foregroundColor(.blue)
                }
            Section(header: Text("Saved Sets")) {
                if store.sets.isEmpty {
                    Text("No sets yet.")
                        .foregroundColor(.secondary)
                } else {
                    List {
                        ForEach(store.sets) { set in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(set.name)
                                    Text("\(extractHanzi(from: set.characters).count) chars")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if store.activeSetId == set.id {
                                    Text("Active").font(.caption).foregroundColor(.blue)
                                } else {
                                    Button("Use") { store.setActive(set) }
                                }
                            }
                        }
                        .onDelete(perform: store.remove)
                    }
                    .frame(minHeight: 200)
                }
            }
        }
        .navigationTitle("Learning Sets")
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
