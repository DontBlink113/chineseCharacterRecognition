import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Section(header: Text("About")) {
                HStack {
                    Text("App Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundColor(Color("Neutral 700"))
                }
            }
            
            Section(header: Text("Legal")) {
                NavigationLink(destination: LicensesView()) {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("Licenses")
                    }
                }
            }

            Section(header: Text("Support")) {
                NavigationLink(destination: FeedbackView()) {
                    HStack {
                        Image(systemName: "envelope")
                        Text("Feedback")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(red: 0.68, green: 0.85, blue: 0.9).ignoresSafeArea())
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { SettingsView() }
    }
}
