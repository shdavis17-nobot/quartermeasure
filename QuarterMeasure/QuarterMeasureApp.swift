//
//  QuarterMeasureApp.swift
//  QuarterMeasure
//
//  Created by Shawn Davis on 3/18/26.
//

import SwiftUI

@main
struct QuarterMeasureApp: App {
    @StateObject private var storeManager = StoreManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(storeManager)
        }
    }
}
