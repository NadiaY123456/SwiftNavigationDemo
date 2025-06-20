//
//  ContentView.swift
//  NavMeshDemo
//
//  Created by Miguel de Icaza on 9/15/23.
//

import CRecast
import RealityKit
import RealityKitContent
import SwiftNavigation
import SwiftUI

struct ContentView: View {
    @State private var showImmersiveSpace = false
    @State private var immersiveSpaceIsShown = false

    static let meshFiles = ["plane", "dungeon", "undulating", "nav_test"]
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

            Task {
                if newValue {
//                    // Print the size of dtLink structure
//                    print("Size of dtLink: \(MemoryLayout<dtLink>.size)")
//                    print("Size of dtPolyRef: \(MemoryLayout<dtPolyRef>.size)")
//
//                    // Check if DT_POLYREF64 is enabled by examining sizes
//                    if MemoryLayout<dtPolyRef>.size == 8 {
//                        print("Using 64-bit polygon references (DT_POLYREF64 enabled)")
//                    } else if MemoryLayout<dtPolyRef>.size == 4 {
//                        print("Using 32-bit polygon references (DT_POLYREF64 disabled)")
//                    } else {
//                        print("Unknown polygon reference size: \(MemoryLayout<dtPolyRef>.size)")
//                    }

                    // Generate mesh from red channel of splat.png
                    
                    // Generate mesh from image
                    if let result = await generateMeshFromImage(
                        named: "splat.png",
                        channel: .green,
                        maxEdgeLength: 50.0,
                        simplificationTolerance: 0.0001,
                        threshold: 0.05
                    ) {
                        let (vertices, indices) = result
                                    
                        // Create mesh entity
                        if let meshEntity = createMeshEntity(
                            vertices: vertices,
                            indices: indices,
                            scale: 0.005, // 0.5mm per pixel for a ~1m wide result
                            color: .green
                        ) {
                            meshEntity.name = "SplatMesh"
                                        
                            // Position it in front of the user
                            meshEntity.position = SIMD3<Float>(0, 1.5, -2) // 1.5m high, 2m forward
                                        
                            spaceOrigin.addChild(meshEntity)
                        }
                                    
//                        // Optional: Add debug vertices to see the mesh points
//                        let debugVertices = createDebugVertexEntity(
//                            vertices: vertices,
//                            scale: 0.0005,
//                            vertexSize: 0.005 // 5mm spheres
//                        )
//                        debugVertices.position = SIMD3<Float>(0, 1.5, -2)
//                        debugVertices.name = "DebugVertices"
//                        spaceOrigin.addChild(debugVertices)
                    }
                    
                    
                    do {
//                        try testCustomAreaLoader()
#if false
                        let selectedMesh = "plane2"

//                        try debugBinFindPath(selectedMesh: selectedMesh)
//                        print ("debugBinFindPath function run successfully for \(selectedMesh)")

                        if let navMeshGeometry = try testGeometry(selectedMesh: selectedMesh) {
                            diagnostic = "\nTestGeoemetry Function run successfully for \(selectedMesh)"
                            print(diagnostic)
                            let navMeshSampleEntity = navMeshGeometry.makeNavMeshEntity()
                            print("NavMesh Sample Entity created successfully")
                            spaceOrigin.addChild(navMeshSampleEntity)
                            print("NavMesh Sample Entity added to spaceOrigin at position \(navMeshSampleEntity.position) and scale \(navMeshSampleEntity.scale)")

                            // 2. Asynchronously load the USDZ model
                            Task {
                                do {
                                    let planeModelEntity = try await ModelEntity(named: "plane")
                                    // set scale to 1
                                    planeModelEntity.scale = .init(x: 1, y: 1, z: 1)
                                    // add the model to the spaceOrigin
                                    spaceOrigin.addChild(planeModelEntity)
                                    print("Loaded plane model at position \(planeModelEntity.position), scale \(planeModelEntity.scale)")
                                } catch {
                                    print("Error loading plane.usdz:", error)
                                }
                            }

                        } else {
                            diagnostic = "TestGeometry returned nil for \(selectedMesh)"
                            print(diagnostic)
                        }
#endif
                    } catch {
                        diagnostic = "TestGeoemetry failed: \(error)"
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
