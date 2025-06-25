
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
    @AppStorage("showPath") private var showPath = true
    @AppStorage("pathGenerationTrigger") private var pathGenerationTrigger = 0

    // Cached scene pieces
    @State private var container = Entity() // holds everything we build
    @State private var contentRoot: Entity? // the inner root returned by the builder
    @State private var navMeshEntity: Entity?
    @State private var terrainEntity: Entity?
    @State private var pathEntity: Entity?
    @State private var sceneBuilt = false

    // NavMesh query components
    @State private var navMesh: NavMesh?
    @State private var navQuery: NavMeshQuery?
    @State private var queryFilter: NavQueryFilter?
    @State private var areaConfig: [SplatAreaConfig] = []

    var body: some View {
        RealityView { content in
            content.add(spaceOrigin)
        }
        .task { // build once
            guard !sceneBuilt else { return }
            await buildSceneOnce()
            updateVisibility()
        }
        .onChange(of: showTerrain) { _, _ in updateVisibility() }
        .onChange(of: showNavMesh) { _, _ in updateVisibility() }
        .onChange(of: showPath) { _, _ in updateVisibility() }
        .onChange(of: pathGenerationTrigger) { _, _ in
            Task { await generateRandomPath() }
        }
    }

    // MARK: – Build only once

    @MainActor
    private func buildSceneOnce() async {
        // Attach an empty container to world origin
        spaceOrigin.addChild(container)

        // Configure areas for your splat_rgba file
        // Green channel = roads (low cost)
        // Blue channel = lakes (very high cost, effectively impassable)
        areaConfig = [
            SplatAreaConfig(
                splatName: "splat_rgba",
                channelConfigs: [
                    // Green channel: Roads - preferred paths with low cost
                    SplatAreaConfig.ChannelConfig(channel: .green, areaCode: 2, cost: 0.3),
                    // Blue channel: Lakes - very high cost (agents will avoid)
                    SplatAreaConfig.ChannelConfig(channel: .blue, areaCode: 3, exclude: true)
                    // You can add red/alpha channels if needed:
                    // SplatAreaConfig.ChannelConfig(channel: .red, areaCode: 4, cost: 2.0),
                    // SplatAreaConfig.ChannelConfig(channel: .alpha, areaCode: 5, cost: 3.0)
                ]
            )
        ]

        let splatFiles = ["splat_rgba"]
        //        let splatFiles: [String] = []
        let terrainFileUSDZ = "foothillUSDZ_centered.usdz"
        //      let terrainFileUSDZ = "plane.usdz"

        //      let terrainFileObj = "/Users/nata/GitHub/Practicing/SwiftNavigationDemo/NavMeshDemo/Data/plane.obj"
        let exportDir = "/Users/nata/Library/CloudStorage/OneDrive-Personal/CNC/VisionPro/World/"

        // Store the NavMesh for path queries
        let (navMeshResult, _) = await buildFoothillNavMeshExample(
            on: container,
            terrainFile: terrainFileUSDZ,
            display: .both,
            splatFiles: splatFiles,
            splatRotationDegrees: 90,
            areaCodeConfig: areaConfig,
            exportDirectory: exportDir
        )

        if let mesh = navMeshResult {
            navMesh = mesh
            // Create query for pathfinding
            do {
                navQuery = try mesh.makeQuery()

                // Create and configure the query filter with area costs
                let qFilter = NavQueryFilter()
                qFilter.configure(with: areaConfig) // set per-area costs
                navQuery?.filter = qFilter // make the query use it
                queryFilter = qFilter // keep a reference if you need it

                // Automatically report the query’s channel flags
                print("✅ NavMeshQuery created with area costs:")
                // Loop through your areaConfig to reflect whatever channels & costs you set
                for cfg in areaConfig {
                    for ch in cfg.channelConfigs {
                        let exclText = ch.exclude ? " (excluded)" : ""
                        print("   - \(ch.channel): areaCode = \(ch.areaCode), cost = \(ch.cost)\(exclText)")
                    }
                }

            } catch {
                print("❌ Failed to create NavMeshQuery: \(error)")
            }
        }

        // The builder added its own root under `container`.
        guard let root = container.children.first else { return }
        contentRoot = root

        // The small patch below (see NavMeshGenerator.swift) gives us names.
        navMeshEntity = root.findEntity(named: "NavMesh")
        terrainEntity = root.findEntity(named: "Terrain")

        sceneBuilt = true
    }

    // MARK: – Path Generation

    @MainActor
    private func generateRandomPath() async {
        guard let query = navQuery else {
            print("❌ No NavMeshQuery available")
            return
        }

        // Remove existing path
        pathEntity?.removeFromParent()
        pathEntity = nil

        do {
            // Find random start and end points
            let start = try query.findRandomPoint().get()
            let end = try query.findRandomPoint().get()

            print("🎯 Generating path from \(start.point3) to \(end.point3)")

            // Find path corridor
            let corridor = try query.findPathCorridor(start: start, end: end).get()

            // Find straight path
            let options: NavMeshQuery.StraightPathOptions = [.allCrossings]
            let foundPath = try query.findStraightPath(
                startPos: start.point3,
                endPos: end.point3,
                pathCorridor: corridor,
                options: options
            ).get()

            print("✅ Found path with \(foundPath.count) waypoints")

            // Create visual representation
            let newPathEntity = foundPath.makePathEntity(
                lineColor: .systemGreen,
                lineRadius: 1,
                waypointRadius: 2.4,
                showWaypoints: true
            )
            newPathEntity.name = "GeneratedPath"

            // Apply same transform as other entities
            if let root = contentRoot {
                newPathEntity.position = -getContentCenter()
                let offsetTowardsCamera: Float = 1
                // …then bump out along world Z so it renders in front of the navmesh
                newPathEntity.position.z += offsetTowardsCamera
                newPathEntity.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
                root.addChild(newPathEntity)
                pathEntity = newPathEntity

                // Update visibility
                updateVisibility()
            }

        } catch {
            print("❌ Path generation failed: \(error)")
        }
    }

    // MARK: – Helper to get content center

    @MainActor
    private func getContentCenter() -> SIMD3<Float> {
        // Compute everything in the same local space we parent the path into
        guard let root = contentRoot else { return .zero }

        if let nav = navMeshEntity {
            let bounds = nav.visualBounds(relativeTo: root)
            return bounds.center
        } else if let terr = terrainEntity {
            let bounds = terr.visualBounds(relativeTo: root)
            return bounds.center
        }
        return .zero
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

        if showPath {
            if let path = pathEntity, path.parent == nil { root.addChild(path) }
        } else {
            pathEntity?.removeFromParent()
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
