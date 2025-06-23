//
//  ImmersiveView.swift
//  NavMeshDemo
//
//  Fully-immersive RealityView: terrain stands up in XY, faces you, and is framed.
//
import SwiftUI
import RealityKit
import SwiftNavigation      // NavMeshGeometry + makeNavMeshEntity + boundingSphere()

let spaceOrigin = Entity()  // your world root

struct ImmersiveView: View {
    var body: some View {
        RealityView { content in

            // 1️⃣ Load or generate your nav-mesh geometry
            guard let navMeshGeometry = try? testGeometry(
                    selectedMesh: "swiftNavMeshGeometryTester")
            else {
                print("❌ Failed to load nav-mesh")
                return
            }

            // 2️⃣ Create the flat XZ entity (uncentered)
            let meshEntity = navMeshGeometry.makeNavMeshEntity(
                showEdges: true,
                edgeRadius: 0.5
            )

            // 3️⃣ Get its true centre & radius
            let (centre, radius) = navMeshGeometry.boundingSphere()

//            // 4️⃣ Recenter so geometry’s centre → (0,0,0)
//            meshEntity.position = -centre

            // 5️⃣ Rotate XZ → XY so “front” faces you
            meshEntity.orientation = simd_quatf(
                angle: .pi/2,        // –90° about X
                axis:  [1, 0, 0]
            )

            // 6️⃣ Compute how far forward (–Z) to place it:
            //    distance = radius / sin(fov/2), with 10% padding
            let fov: Float = .pi / 3   // ≈60° vertical FOV
            let distance = radius / sin(fov * 0.5) * 1.1

            // 7️⃣ Build a little root, shift it forward, and add mesh
            let root = Entity()
            root.position = [0, 0, -distance]
            root.addChild(meshEntity)

            // 8️⃣ Send into the immersive world
            content.add(root)
        }
    }
}
