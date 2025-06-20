//
//  NavMeshDemoApp.swift
//  NavMeshDemo
//
//  Created by Miguel de Icaza on 9/15/23.
//

import SwiftUI

@main
struct NavMeshDemoApp: App {
    // We’ll launch straight into full immersion
    var body: some Scene {
        // You can keep your normal WindowGroup if you still want a windowed entry point:
        WindowGroup {
            ContentView()
        }

        // Define a fully immersive space
        ImmersiveSpace(id: "ImmersiveSpace") {
            // This is the view you already built in ImmersiveView.swift
            ImmersiveView()
        }
        // Force the space to obscure everything and go “full” immersion
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
