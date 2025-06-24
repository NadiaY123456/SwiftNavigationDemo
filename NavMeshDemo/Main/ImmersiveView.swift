//
//  ImmersiveView.swift
//  NavMeshDemo
//
//  Fully-immersive RealityView: terrain stands up in XY, faces you, and is framed.
//
import RealityKit
import SwiftNavigation // NavMeshGeometry + makeNavMeshEntity + boundingSphere()
import SwiftUI

let spaceOrigin = Entity() // your world root

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
