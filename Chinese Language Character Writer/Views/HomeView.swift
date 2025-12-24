import SwiftUI

struct HomeView: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.68, green: 0.85, blue: 0.9)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    // Top bar with Profile button
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            // Profile action - not implemented yet
                        }) {
                            Image(systemName: "person.circle.fill")
                                .font(.title2)
                                .foregroundColor(Color("Blue 900"))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)

                    Spacer()

                    Text("Chinese Character Writing")
                        .font(.system(size: 60)).bold()
                        .foregroundColor(Color("Blue 900"))
                        .padding(.bottom, 30)

                    HStack(spacing: 24) {
                        NavigationLink(destination: SentencePracticeView()) {
                            Text("Sentence Practice")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(Color("Sand 100"))
                                .padding(.horizontal, 28)
                                .padding(.vertical, 20)
                                .frame(minWidth: 200)
                                .background(Color("Blue 700"))
                                .cornerRadius(14)
                                .shadow(color: Color("Blue 700").opacity(0.3), radius: 10, x: 0, y: 5)
                        }

                        NavigationLink(destination: FlashcardPracticeView()) {
                            Text("Flashcards")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(Color("Sand 100"))
                                .padding(.horizontal, 28)
                                .padding(.vertical, 20)
                                .frame(minWidth: 200)
                                .background(Color("Blue 700"))
                                .cornerRadius(14)
                                .shadow(color: Color("Blue 700").opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                    }
                    
                    NavigationLink(destination: CharacterSetsView()) {
                        Text("Set Characters")
                            .font(.title3)
                            .foregroundColor(Color("Blue 900"))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .cornerRadius(10)
                            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
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
