import SwiftUI

struct FlashcardReviewView: View {
    @EnvironmentObject var store: LearningSetsStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    
    @State private var selectedSetId: UUID? = nil
    
    private var selectedSet: LearningSet? {
        if let id = selectedSetId { return store.sets.first { $0.id == id } }
        return store.activeSet
    }
    
    private var flashcardItems: [FlashcardItem] {
        guard let s = selectedSet, let items = s.items else { return [] }
        return items
    }
    
    private var setsWithDefinitions: [LearningSet] {
        store.sets.filter { $0.hasDefinitions }
    }
    
    private var learningSetSelection: Binding<UUID?> {
        Binding(
            get: { selectedSetId ?? store.activeSetId },
            set: { selectedSetId = $0 }
        )
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color("Secondary100")
                    .ignoresSafeArea()
                
                if setsWithDefinitions.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Deck selector
                            deckSelector
                            
                            if selectedSet != nil {
                                // Overall statistics
                                overallStatsCard
                                
                                // Direction-specific stats
                                directionStatsCard
                                
                                // Card list with details
                                cardListSection
                            }
                            
                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                }
            }
            .navigationTitle("Review Progress")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                if selectedSetId == nil {
                    selectedSetId = store.activeSetId
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(Color("Primary600"))
            Text("No Flashcard Sets")
                .font(.title2.bold())
                .foregroundColor(Color("Primary900"))
            Text("Create a flashcard set with definitions to start reviewing")
                .font(.subheadline)
                .foregroundColor(Color("Primary600"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    private var deckSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Deck")
                .font(.headline)
                .foregroundColor(Color("Primary900"))
            
            Picker("Deck", selection: learningSetSelection) {
                ForEach(setsWithDefinitions) { set in
                    Text(set.name).tag(Optional(set.id))
                }
            }
            .pickerStyle(.menu)
            .padding(12)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
    }
    
    private var overallStatsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(Color("Primary700"))
                Text("Overall Progress")
                    .font(.headline)
                    .foregroundColor(Color("Primary900"))
                Spacer()
            }
            
            HStack(spacing: 20) {
                ReviewStatBox(
                    value: "\(flashcardItems.count)",
                    label: "Total Cards",
                    color: Color("Primary900")
                )
                
                ReviewStatBox(
                    value: "0",
                    label: "Due Today",
                    color: .green
                )
                
                ReviewStatBox(
                    value: "\(flashcardItems.count)",
                    label: "Learned",
                    color: Color("Primary700")
                )
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    private var directionStatsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundColor(Color("Primary700"))
                Text("Practice Directions")
                    .font(.headline)
                    .foregroundColor(Color("Primary900"))
                Spacer()
            }
            
            VStack(spacing: 12) {
                // Prompt to Character (Flip mode)
                DirectionRow(
                    icon: "text.bubble",
                    title: "Definition → Character",
                    subtitle: "Flip card practice",
                    dueCount: 0,
                    total: flashcardItems.count
                )
                
                Divider()
                
                // Character to Prompt (Draw mode)
                DirectionRow(
                    icon: "hand.draw",
                    title: "Character → Definition",
                    subtitle: "Writing practice",
                    dueCount: 0,
                    total: flashcardItems.count
                )
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    private var cardListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundColor(Color("Primary700"))
                Text("Card Details")
                    .font(.headline)
                    .foregroundColor(Color("Primary900"))
                Spacer()
            }
            .padding(.horizontal, 4)
            
            VStack(spacing: 8) {
                ForEach(flashcardItems) { card in
                    CardDetailRow(
                        card: card
                    )
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct ReviewStatBox: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(Color("Primary600"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DirectionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let dueCount: Int
    let total: Int
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(Color("Primary700"))
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(Color("Primary900"))
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(Color("Primary600"))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    if dueCount > 0 {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    Text("\(dueCount)")
                        .font(.headline)
                        .foregroundColor(dueCount > 0 ? .orange : .green)
                }
                Text("of \(total) due")
                    .font(.caption2)
                    .foregroundColor(Color("Primary600"))
            }
        }
        .padding(12)
        .background(Color("Secondary100").opacity(0.3))
        .cornerRadius(10)
    }
}

struct CardDetailRow: View {
    let card: FlashcardItem
    
    @State private var isExpanded: Bool = false
    
    private var promptToCharDue: Bool {
        false
    }
    
    private var charToPromptDue: Bool {
        false
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main row
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack(spacing: 12) {
                    Text(card.hanzi)
                        .font(.title2)
                        .foregroundColor(Color("Primary900"))
                        .frame(width: 50)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.definition)
                            .font(.subheadline)
                            .foregroundColor(Color("Primary900"))
                            .lineLimit(1)
                        
                        HStack(spacing: 8) {
                            StatusBadge(isDue: promptToCharDue, label: "Flip")
                            StatusBadge(isDue: charToPromptDue, label: "Draw")
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(Color("Primary600"))
                }
                .padding(12)
            }
            .buttonStyle(.plain)
            
            // Expanded details
            if isExpanded {
                VStack(spacing: 12) {
                    Divider()
                    
                    // Prompt to Char stats
                    CardDirectionDetail(
                        title: "Definition → Character",
                        data: card.promptToChar
                    )
                    
                    Divider()
                    
                    // Char to Prompt stats
                    CardDirectionDetail(
                        title: "Character → Definition",
                        data: card.charToPrompt
                    )
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

struct StatusBadge: View {
    let isDue: Bool
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isDue ? Color.orange : Color.green)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundColor(Color("Primary600"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color("Secondary100").opacity(0.3))
        .cornerRadius(6)
    }
}

struct CardDirectionDetail: View {
    let title: String
    let data: FSRSData
    
    private var nextReviewDate: Date {
        data.due
    }
    
    private var isDue: Bool {
        data.due <= Date()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(Color("Primary900"))
            
            HStack(spacing: 16) {
                DetailItem(label: "Reviews", value: "\(data.reps)")
                DetailItem(label: "Interval", value: "\(data.scheduledDays) days")
                DetailItem(label: "Difficulty", value: String(format: "%.1f", data.difficulty))
            }
            
            HStack(spacing: 8) {
                Image(systemName: isDue ? "clock.fill" : "calendar")
                    .font(.caption)
                    .foregroundColor(isDue ? .orange : Color("Primary700"))
                
                if isDue {
                    Text("Due now")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if data.reps > 0 {
                    Text("Next: \(nextReviewDate, style: .date)")
                        .font(.caption)
                        .foregroundColor(Color("Primary600"))
                } else {
                    Text("Not reviewed yet")
                        .font(.caption)
                        .foregroundColor(Color("Primary600"))
                }
            }
        }
        .padding(10)
        .background(Color("Secondary100").opacity(0.2))
        .cornerRadius(8)
    }
}

struct DetailItem: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(Color("Primary900"))
            Text(label)
                .font(.caption2)
                .foregroundColor(Color("Primary600"))
        }
    }
}

#Preview {
    FlashcardReviewView()
        .environmentObject(LearningSetsStore())
}
