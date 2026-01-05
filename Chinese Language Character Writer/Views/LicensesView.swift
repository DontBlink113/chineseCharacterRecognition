import SwiftUI

struct LicensesView: View {
    @State private var licenses: [LicenseItem] = []
    
    var body: some View {
        List {
            if licenses.isEmpty {
                Text("No license files found in the app bundle.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(licenses) { item in
                    NavigationLink(destination: LicenseDetailView(license: item)) {
                        HStack {
                            Image(systemName: "doc.text")
                            Text(item.title)
                        }
                    }
                }
            }
        }
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(red: 0.68, green: 0.85, blue: 0.9).ignoresSafeArea())
        .task { await loadLicenses() }
    }
    
    private func loadLicenses() async {
        // Prefer files under Licenses/ subdirectory
        var collected: [URL] = Bundle.main.urls(forResourcesWithExtension: "txt", subdirectory: "Licenses") ?? []

        // Fallback: if none found, try top-level bundle for known license filenames
        if collected.isEmpty {
            let known = ["LGPL-3.0.txt", "Arphic-Public-License.txt", "ThirdPartyNotices.txt"]
            for name in known {
                if let url = Bundle.main.url(forResource: (name as NSString).deletingPathExtension,
                                             withExtension: (name as NSString).pathExtension,
                                             subdirectory: nil) {
                    collected.append(url)
                }
            }
        }

        let items: [LicenseItem] = collected
            .sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending })
            .map { url in
                let fileName = url.lastPathComponent
                let base = (fileName as NSString).deletingPathExtension
                return LicenseItem(title: base, fileName: fileName)
            }
        licenses = items
    }
}

struct LicenseItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let fileName: String
}

struct LicenseDetailView: View {
    let license: LicenseItem
    @State private var text: String = ""
    
    var body: some View {
        ScrollView {
            if text.isEmpty {
                Text("Unable to load license text.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(Color("Blue 900"))
                    .padding()
            }
        }
        .background(Color.white)
        .navigationTitle(license.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            text = await loadLicenseText(fileName: license.fileName)
        }
    }
    
    private func loadLicenseText(fileName: String) async -> String {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension

        // 1) Try Licenses/ subdirectory
        if let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "Licenses"),
           let text = readText(from: url) {
            return text
        }

        // 2) Try top-level bundle
        if let url = Bundle.main.url(forResource: base, withExtension: ext),
           let text = readText(from: url) {
            return text
        }

        // 3) Enumerate Licenses/ for case-insensitive match
        if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "Licenses") {
            if let match = urls.first(where: { $0.lastPathComponent.caseInsensitiveCompare(fileName) == .orderedSame }),
               let text = readText(from: match) {
                return text
            }
        }

        // 4) Construct path under resourceURL/Licenses
        if let root = Bundle.main.resourceURL {
            let candidate = root.appendingPathComponent("Licenses").appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: candidate.path), let text = readText(from: candidate) {
                return text
            }
        }

        return ""
    }

    private func readText(from url: URL) -> String? {
        if let data = try? Data(contentsOf: url) {
            // Try UTF-8 first
            if let s = String(data: data, encoding: .utf8) { return s }
            // Fallback encodings
            if let s = String(data: data, encoding: .isoLatin1) { return s }
            if let s = String(data: data, encoding: .utf16) { return s }
        }
        return nil
    }
}

struct LicensesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { LicensesView() }
    }
}
