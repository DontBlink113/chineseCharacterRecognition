import SwiftUI

struct HomeView: View {
    var body: some View {
        ZStack {
            Color(red: 0.68, green: 0.85, blue: 0.9)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                
                // Hero section - title card
                VStack(spacing: 16) {
                    Text("Chinese Character Writing")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundColor(Color("Blue 900"))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    
                    Text("Learning to write chinese characters with intelligent feedback")
                        .font(.title2)
                        .foregroundColor(Color("Blue 900").opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.vertical, 40)
                .padding(.horizontal, 32)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color("Sand 200"))
                        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
                )
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Action buttons - anchored near bottom
                VStack(spacing: 16) {
                    NavigationLink(destination: FlashcardPracticeView()) {
                        Text("Flashcards")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(Color("Sand 100"))
                            .padding(.horizontal, 40)
                            .padding(.vertical, 24)
                            .frame(maxWidth: 400)
                            .background(Color("Blue 700"))
                            .cornerRadius(16)
                            .shadow(
                                color: Color("Blue 700").opacity(0.3),
                                radius: 12,
                                x: 0,
                                y: 6
                            )
                    }
                    
                    NavigationLink(destination: CharacterSetsView()) {
                        Text("Set Characters")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(Color("Blue 900"))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .frame(maxWidth: 280)
                            .background(Color.white)
                            .cornerRadius(12)
                            .shadow(
                                color: Color.black.opacity(0.1),
                                radius: 6,
                                x: 0,
                                y: 3
                            )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 220)
            }
        }
    }
}
