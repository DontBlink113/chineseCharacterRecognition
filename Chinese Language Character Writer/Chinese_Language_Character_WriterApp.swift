//
//  Chinese_Language_Character_WriterApp.swift
//  Chinese Language Character Writer
//
//  Created by Keane Haesle on 11/18/25.
//

import SwiftUI

@main
struct Chinese_Language_Character_WriterApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
            }
            .environmentObject(LearningSetsStore())
            .navigationViewStyle(.stack) // This ensures a standard navigation stack on all devices
            .preferredColorScheme(.light)
        }
    }
}
