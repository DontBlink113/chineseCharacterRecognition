import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Section(header: Text("About")) {
                HStack {
                    Text("App Version 1.0.2")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundColor(Color("Primary600"))
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
        .background(Color("Secondary100").ignoresSafeArea())
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { SettingsView() }
    }
}
