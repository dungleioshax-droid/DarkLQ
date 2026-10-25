//
//  External_DarkSwordApp.swift
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/3/26.
//

import SwiftUI

@main
struct External_DarkSwordApp: App {
    @StateObject private var manager = DarkSwordManager()

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager)
        }
    }
}
