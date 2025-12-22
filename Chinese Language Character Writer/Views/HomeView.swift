import SwiftUI

struct HomeView: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color("Blue 900"), location: 0.0),
                        .init(color: Color("Blue 300"), location: 0.35),
                        .init(color: Color("Sand 100"), location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    // Top bar with Set Characters and Profile buttons
                    HStack {
                        NavigationLink(destination: CharacterSetsView()) {
                            Text("Set Characters")
                                .font(.subheadline)
                                .foregroundColor(Color("Blue 900"))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color("Sand 100"))
                                .cornerRadius(8)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            // Profile action - not implemented yet
                        }) {
                            Image(systemName: "person.circle.fill")
                                .font(.title2)
                                .foregroundColor(Color("Sand 100"))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)

                    Spacer()

                    Text("Ocean: Chinese Character Writing")
                        .font(.system(size: 60)).bold()
                        .foregroundColor(Color("Blue 900"))

                    HStack(spacing: 20) {
                        NavigationLink(destination: SentencePracticeView()) {
                            Text("Sentence Practice")
                                .font(.title3)
                                .foregroundColor(Color("Sand 100"))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .frame(maxWidth: 220)
                                .background(Color("Blue 700"))
                                .cornerRadius(12)
                                .shadow(color: Color("Blue 700").opacity(0.25), radius: 8, x: 0, y: 4)
                        }

                        NavigationLink(destination: FlashcardPracticeView()) {
                            Text("Flashcards")
                                .font(.title3)
                                .foregroundColor(Color("Sand 100"))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .frame(maxWidth: 220)
                                .background(Color("Blue 700"))
                                .cornerRadius(12)
                                .shadow(color: Color("Blue 700").opacity(0.25), radius: 8, x: 0, y: 4)
                        }
                    }
                    
                    Spacer()
                }
            }
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { HomeView() }
            .environmentObject(LearningSetsStore())
    }
}
