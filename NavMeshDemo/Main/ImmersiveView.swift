
//  ImmersiveView.swift
//  NavMeshDemo
//
//  Updated: 24 Jun 2025
//

//
//  ImmersiveView.swift
//  NavMeshDemo
//
//  Generates the terrain + nav-mesh exactly once, then just
//  adds/removes those entities when the user toggles them.
//

import RealityKit
import SwiftNavigation
import SwiftUI

/// Global root that RealityView anchors to the world-origin
let spaceOrigin = Entity()

struct ImmersiveView: View {
    // Shared settings coming from the plackard
    @AppStorage("showTerrain") private var showTerrain = true
    @AppStorage("showNavMesh") private var showNavMesh = true

    // Cached scene pieces
    @State private var container      = Entity()   // holds everything we build
    @State private var contentRoot: Entity?        // the inner root returned by the builder
    @State private var navMeshEntity: Entity?
    @State private var terrainEntity: Entity?
    @State private var sceneBuilt     = false

    var body: some View {
        RealityView { content in
            content.add(spaceOrigin)
        }
        .task {                                             // build once
            guard !sceneBuilt else { return }
            await buildSceneOnce()
            updateVisibility()
        }
        .onChange(of: showTerrain) { _, _ in updateVisibility() }
        .onChange(of: showNavMesh) { _, _ in updateVisibility() }
    }

    // MARK: – Build only once
    @MainActor
    private func buildSceneOnce() async {
        // Attach an empty container to world origin
        spaceOrigin.addChild(container)

        // Build *both* visuals so scale/camera are correct,
        // even if the user immediately hides one of them.
        await buildFoothillNavMeshExample(
            on: container,
            terrainFile: "plane.usdz", //"foothillUSDZ_centered.usdz",
            display: .both,                         // <— always both
            splatFile: "splat_rgba",
            splatRotationDegrees: 90,
            exportDirectory: "/Users/nata/Library/CloudStorage/"
                             + "OneDrive-Personal/CNC/VisionPro/World/"
        )

        // The builder added its own root under `container`.
        guard let root = container.children.first else { return }
        contentRoot = root

        // The small patch below (see NavMeshGenerator.swift) gives us names.
        navMeshEntity  = root.findEntity(named: "NavMesh")
        terrainEntity  = root.findEntity(named: "Terrain")

        sceneBuilt = true
    }

    // MARK: – Toggle visibility without regenerating
    @MainActor
    private func updateVisibility() {
        guard let root = contentRoot else { return }

        if showTerrain {
            if let terr = terrainEntity, terr.parent == nil { root.addChild(terr) }
        } else {
            terrainEntity?.removeFromParent()
        }

        if showNavMesh {
            if let nav = navMeshEntity, nav.parent == nil { root.addChild(nav) }
        } else {
            navMeshEntity?.removeFromParent()
        }
    }
}

// MARK: – Tiny helper to search recursively by name
private extension Entity {
    func findEntity(named target: String) -> Entity? {
        if name == target { return self }
        for child in children {
            if let found = child.findEntity(named: target) { return found }
        }
        return nil
    }
}



#if false
let testNameMeshGeometryBool = false
let testCustomAreaLoaderBool = false
let generateSplatModelBool = false
let buildFoothillNavMeshExampleBool = true

struct ImmersiveView: View {
    var body: some View {
        RealityView { content in

            // FULL END-TO-END GENERATION WITH CUSTOM AREAS
            if buildFoothillNavMeshExampleBool {
                Task {
                    let splatFile = "splat_rgba"
                    let terrainFileUSDZ = "foothillUSDZ_centered.usdz"
//                    let terrainFileUSDZ = "plane.usdz"

//                    let terrainFileObj = "/Users/nata/GitHub/Practicing/SwiftNavigationDemo/NavMeshDemo/Data/plane.obj"
                    let exportDir = "/Users/nata/Library/CloudStorage/OneDrive-Personal/CNC/VisionPro/World/"

                    // Build + export both OBJ and BIN
                    await buildFoothillNavMeshExample(
                        on: spaceOrigin,
                        terrainFile: terrainFileUSDZ, // "/path/to/plane.obj" or "plane.usdz"
                        display: .both,
                        splatFile: splatFile,
                        splatRotationDegrees: 90,
                        exportDirectory: exportDir
                    )
                }
            }

            // LOAD CUSTOM AREAS
            if testCustomAreaLoaderBool {
                Task {
                    try testCustomAreaLoader(printStats: true)
                }
            }

            // GENERATE SPLAT MODEL / OBJ
            if generateSplatModelBool {
                Task {
                    try await generateSplatModel(
                        terrainName: "plane",
                        terrainRotation: simd_quatf(angle: .pi / 2, axis: [0, 1, 0]),
                        splatName: "splat_rgba.png",
                        channel: .blue,
                        maxEdgeLength: 50,
                        simplificationTolerance: 0.001,
                        threshold: 0.1, // nil, //(nil = auto)
                        invertMask: false, // (nil = auto),
                        morphologyRadius: 0, // Try reducing or removing morphology for images with distinct regions to avoid eroding thin features: 0, otherwise 2
                        interiorSpacingFactor: 1000 // interiorSpacing = maxEdgeLength * interiorSpacingFactor
                    )
                }
            }

            // TEST NAVMESH GEOMETRY
            if testNameMeshGeometryBool {
                // 1️⃣ Load or generate your nav-mesh geometry
                guard let navMeshGeometry = try? testGeometry(selectedMesh: "foothillUSDZ")
                else {
                    print("❌ Failed to load nav-mesh")
                    return
                }

                // 2️⃣ Create the flat XZ entity (uncentered)
                let meshEntity = navMeshGeometry.makeNavMeshEntity(
                    showEdges: true,
                    edgeRadius: 0.5
                )

                // 3️⃣ Get its true center & radius
                let (center, radius) = navMeshGeometry.boundingSphere()

                //            // 4️⃣ Recenter so geometry’s center → (0,0,0)
                //            meshEntity.position = -center

                // 5️⃣ Rotate XZ → XY so “front” faces you
                meshEntity.orientation = simd_quatf(
                    angle: .pi / 2, // –90° about X
                    axis: [1, 0, 0]
                )

                // 6️⃣ Compute how far forward (–Z) to place it:
                //    distance = radius / sin(fov/2), with 10% padding
                let fov: Float = .pi / 3 // ≈60° vertical FOV
                let distance = radius / sin(fov * 0.5) * 1.1

                // 7️⃣ Build a little root, shift it forward, and add mesh
                meshEntity.position = [0, 0, -distance]
                spaceOrigin.addChild(meshEntity)
            }

            // 8️⃣ Send into the immersive world
            content.add(spaceOrigin)
        }
    }
}
#endif
