import SwiftUI

struct FeedbackView: View {
    @State private var copied = false
    
    private var feedbackEmail: String {
        (Bundle.main.object(forInfoDictionaryKey: "FeedbackEmail") as? String) ?? "keanehaesle@gmail.com"
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Hi! My name is Keane")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(Color("Blue 900"))
                    .padding(.top, 8)

                Text("I'm building intelligent software for learning Chinese characters, and your feedback is crucial to help me improve this app.")
                    .font(.body)
                    .foregroundColor(Color("Neutral 700"))
                    .lineSpacing(6)

                Text("Please email me with any suggestions and I respond and make changes as soon as I can! \n\nAll the best,\nKeane")
                    .font(.body)
                    .foregroundColor(Color("Neutral 700"))
                    .lineSpacing(6)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.headline)
                        .foregroundColor(Color("Blue 900"))

                    HStack(spacing: 12) {
                        Text(feedbackEmail)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(Color("Blue 900"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Copy") {
                            UIPasteboard.general.string = feedbackEmail
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copied = false
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    if copied {
                        Text("Copied to clipboard")
                            .font(.caption)
                            .foregroundColor(Color("Neutral 700"))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .navigationTitle("Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
    }
}

struct FeedbackView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { FeedbackView() }
    }
}
