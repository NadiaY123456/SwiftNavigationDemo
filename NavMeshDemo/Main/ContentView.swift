//
//  ContentView.swift
//  NavMeshDemo
//
//  Updated: 24 Jun 2025
//

import CRecast
import RealityKit
import RealityKitContent
import SwiftNavigation
import SwiftUI

struct ContentView: View {
    // MARK: – App-wide visibility settings

    @AppStorage("showTerrain") private var showTerrain = true
    @AppStorage("showNavMesh") private var showNavMesh = true

    // MARK: – Immersive-space state

    @State private var showImmersiveSpace = false
    @State private var immersiveSpaceShown = false
    @State private var diagnostic = ""

    // MARK: – Vision-OS helpers

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        VStack(spacing: 28) {
            Model3D(named: "Scene", bundle: realityKitContentBundle)

            Text("Navigation Mesh Explorer")

            // — Load / Unload Immersive Space —
            Toggle("Load Scene", isOn: $showImmersiveSpace)
                .toggleStyle(.button)

            // — NEW: Visibility Toggles —
            HStack(spacing: 24) {
                Toggle(isOn: $showTerrain) {
                    Text(showTerrain ? "Hide Terrain" : "Show Terrain")
                }
                .toggleStyle(.button)

                Toggle(isOn: $showNavMesh) {
                    Text(showNavMesh ? "Hide NavMesh" : "Show NavMesh")
                }
                .toggleStyle(.button)
            }

            Text(diagnostic)
                .font(.footnote)
                .opacity(0.6)
        }
        .padding(40)
        .onChange(of: showImmersiveSpace) { _, newValue in
            Task {
                if newValue {
                    switch await openImmersiveSpace(id: "ImmersiveSpace") {
                    case .opened: immersiveSpaceShown = true
                    case .error, .userCancelled:
                        immersiveSpaceShown = false
                        showImmersiveSpace = false
                    @unknown default:
                        immersiveSpaceShown = false
                        showImmersiveSpace = false
                    }
                } else if immersiveSpaceShown {
                    await dismissImmersiveSpace()
                    immersiveSpaceShown = false
                }
            }
        }
    }
}
