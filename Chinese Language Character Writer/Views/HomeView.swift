import SwiftUI

struct HomeView: View {
    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.12), Color.blue.opacity(0.04)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer(minLength: 40)

                Text("Chinese Sentence Writing Practice")
                    .font(.largeTitle).bold()
                    .foregroundColor(.blue)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Text("Start the automatic Chinese sentence writing autograder to practice writing sentences and characters.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                NavigationLink(destination: SentencePracticeView()) {
                    Text("Start Autograder")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: 200)
                        .background(Color.blue)
                        .cornerRadius(12)
                        .shadow(color: Color.blue.opacity(0.25), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal)

                NavigationLink(destination: CharacterSetsView()) {
                    Text("Create Character Sets")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: 200)
                        .background(Color.blue)
                        .cornerRadius(12)
                        .shadow(color: Color.blue.opacity(0.25), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal)

                NavigationLink(destination: FlashcardPracticeView()) {
                    Text("Flashcards")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: 200)
                        .background(Color.blue)
                        .cornerRadius(12)
                        .shadow(color: Color.blue.opacity(0.25), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal)

                Spacer()
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { HomeView() }
            .environmentObject(LearningSetsStore())
    }
}
