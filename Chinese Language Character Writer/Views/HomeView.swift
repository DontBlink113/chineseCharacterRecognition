import SwiftUI

struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    var body: some View {
        ZStack {
            Color("Secondary100")
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                
                // Hero section - title card
                VStack(spacing: 16) {
                    Text("Chinese Character Writing")
                        .font(.system(size: horizontalSizeClass == .compact ? 32 : 52, weight: .bold))
                        .foregroundColor(Color("Primary700"))
                        .multilineTextAlignment(.center)
                        .lineLimit(horizontalSizeClass == .compact ? 3 : 2)
                        .minimumScaleFactor(0.7)
                    
                    Text("Learn to write characters with spaced repetition.")
                        .font(.title2)
                        .foregroundColor(Color("Primary600").opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.vertical, 40)
                .padding(.horizontal, 32)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color("Secondary100"))
                        .shadow(color: Color("Primary300").opacity(0.25), radius: 16, x: 0, y: 8)
                )
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Action buttons - anchored near bottom
                VStack(spacing: 14) {
                    NavigationLink(destination: FlashcardPracticeView()) {
                        Text("Flashcards")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(Color("Secondary100"))
                            .padding(.horizontal, 36)
                            .padding(.vertical, 20)
                            .frame(maxWidth: 360)
                            .background(Color("Primary600"))
                            .cornerRadius(14)
                            .shadow(
                                color: Color("Primary500").opacity(0.2),
                                radius: 10,
                                x: 0,
                                y: 4
                            )
                    }
                    
                    NavigationLink(destination: FlashcardReviewView()) {
                        HStack(spacing: 8) {
                            Image(systemName: "chart.bar.fill")
                                .font(.body)
                            Text("Review Progress")
                        }
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(Color("Primary600"))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .frame(maxWidth: 260)
                        .background(Color("Secondary200"))
                        .cornerRadius(10)
                        .shadow(
                            color: Color("Neutral400").opacity(0.15),
                            radius: 4,
                            x: 0,
                            y: 2
                        )
                    }
                    
                    NavigationLink(destination: CharacterSetsView()) {
                        Text("Set Characters")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(Color("Primary600"))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .frame(maxWidth: 260)
                            .background(Color("Secondary200"))
                            .cornerRadius(10)
                            .shadow(
                                color: Color("Neutral400").opacity(0.15),
                                radius: 4,
                                x: 0,
                                y: 2
                            )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)

                // Bottom prompt
                NavigationLink(destination: FeedbackView()) {
                    HStack(spacing: 6) {
                        Text("Have feedback?")
                            .foregroundColor(Color("Neutral700"))
                        Text("click here")
                            .foregroundColor(Color("Primary500"))
                            .underline()
                    }
                    .font(.subheadline)
                    .padding(10)
                }
                .padding(.bottom, 24)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape")
                        .imageScale(.large)
                        .foregroundColor(Color("Primary600"))
                }
            }
        }
    }
}
