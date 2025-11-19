//
//  Chinese_Language_Character_WriterApp.swift
//  Chinese Language Character Writer
//
//  Created by Keane Haesle on 11/18/25.
//

import SwiftUI
import SwiftData

@main
struct Chinese_Language_Character_WriterApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
