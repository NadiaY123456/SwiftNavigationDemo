//
//  ContentView.swift
//  NavMeshDemo
//
//  Created by Miguel de Icaza on 9/15/23.
//

import RealityKit
import RealityKitContent
import SwiftNavigation
import SwiftUI
import CRecast

struct ContentView: View {
    @State private var showImmersiveSpace = false
    @State private var immersiveSpaceIsShown = false

    static let meshFiles = ["dungeon", "undulating", "nav_test"]
    @State var selectedMesh = ContentView.meshFiles[0]
    @State var diagnostic = ""
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    var body: some View {
        VStack {
            Model3D(named: "Scene", bundle: realityKitContentBundle)
                .padding(.bottom, 50)

            Text("Navigation Mesh Explorer")

            Picker("Pick Mesh", selection: $selectedMesh) {
                ForEach(ContentView.meshFiles, id: \.self) {
                    Text($0)
                }
            }
            Toggle("Load Mesh", isOn: $showImmersiveSpace)
                .toggleStyle(.button)
                .padding(.top, 50)
            Text(diagnostic)
        }
        .padding()
        .onChange(of: showImmersiveSpace) { _, newValue in
#if false
            // Load obj input
            guard let file = Bundle.main.url(forResource: selectedMesh, withExtension: "obj") else {
                diagnostic = "Could not find the mesh \(selectedMesh).obj"
                print("Could not find the mesh \(selectedMesh).obj")
                return
            }
            print("Loaded mesh \(file)")
#endif

           

            Task {
                if newValue {
                    // Print the size of dtLink structure
                    print("Size of dtLink: \(MemoryLayout<dtLink>.size)")
                    print("Size of dtPolyRef: \(MemoryLayout<dtPolyRef>.size)")

                    // Check if DT_POLYREF64 is enabled by examining sizes
                    if MemoryLayout<dtPolyRef>.size == 8 {
                        print("Using 64-bit polygon references (DT_POLYREF64 enabled)")
                    } else if MemoryLayout<dtPolyRef>.size == 4 {
                        print("Using 32-bit polygon references (DT_POLYREF64 disabled)")
                    } else {
                        print("Unknown polygon reference size: \(MemoryLayout<dtPolyRef>.size)")
                    }

                    do {
                        // 1. load the nav‑mesh
//                        try testLoader()
//                        diagnostic = "NavMesh built successfully"
//                        print("NavMesh built successfully")
                        try testBinFindPath()
                        diagnostic = "\nPathfinding BIN test completed successfully"
                        print(diagnostic)
                    } catch {
                        diagnostic = "NavMesh load failed: \(error)"
                        print(diagnostic)
                    }

#if false
                    // Run the navmesh test loader
                    do {
                        try testLoader()
                        diagnostic = "NavMesh built successfully"
                        print("NavMesh built successfully")
                        try testFindPath()
                        diagnostic += "\nPathfinding test completed successfully"
                        print(diagnostic)
                    } catch {
                        diagnostic = "NavMesh or pathfinding build failed: \(error)"
                        print(diagnostic)
                    }
#endif
                    switch await openImmersiveSpace(id: "ImmersiveSpace") {
                    case .opened:
                        immersiveSpaceIsShown = true
                    case .error, .userCancelled:
                        fallthrough
                    @unknown default:
                        immersiveSpaceIsShown = false
                        showImmersiveSpace = false
                    }
                } else if immersiveSpaceIsShown {
                    await dismissImmersiveSpace()
                    immersiveSpaceIsShown = false
                }
            }
        }
    }
}
