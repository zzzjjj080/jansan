//
//  JansanApp.swift
//  Jansan
//
//  Created by jin on 2026/08/14.
//

import SwiftUI
import SwiftData

@main
struct JansanApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: SavedGame.self)
    }
}
