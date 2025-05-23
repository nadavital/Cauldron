//
//  CauldronApp.swift
//  Cauldron
//
//  Created by Nadav Avital on 5/6/25.
//

import SwiftUI
import Firebase

@main
struct CauldronApp: App {
    @StateObject private var authViewModel = AuthViewModel()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            if authViewModel.user != nil {
                ContentView()
                    .environmentObject(authViewModel)
            } else {
                LoginView()
                    .environmentObject(authViewModel)
            }
        }
    }
}
