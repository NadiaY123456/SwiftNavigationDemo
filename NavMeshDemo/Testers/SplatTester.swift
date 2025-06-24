//
//  SplatTester.swift
//  NavMeshDemo
//
//  Created by Nadia Yilmaz on 6/20/25.
//

import RealityKit
import UIKit
import SwiftNavigation

/// Handy wrapper that loads a UIImage, runs `SplatMeshGenerator`,
/// prints some stats, and hands the full 2-D mesh bundle back.
///
/// - Returns: `MeshResult2D` (vertices + indices + imageSize) or `nil` on failure.
@MainActor
func generateMeshFromImage(
    named imageName: String,
    channel: SplatMeshGenerator.Channel,
    maxEdgeLength: CGFloat,
    simplificationTolerance: CGFloat,
    threshold: Float?,
    invertMask: Bool?,
    morphologyRadius: Int,
    interiorSpacingFactor: CGFloat
) async -> MeshResult2D? {
    guard let image = UIImage(named: imageName) else {
        print("❌  Failed to load image “\(imageName)”")
        return nil
    }

    print("Using channel=\(channel)  threshold=\(threshold ?? -1)  invertMask=\(invertMask)")

    let meshGen = SplatMeshGenerator(
        maxEdgeLength: maxEdgeLength,
        simplificationTolerance: simplificationTolerance,
        threshold: threshold,
        channel: channel,
        invertMask: invertMask,
        morphologyRadius: morphologyRadius,
        interiorSpacingFactor: interiorSpacingFactor
    )

    do {
        // save black and white mask version for debugging
        let maskURL = URL(fileURLWithPath:
            "/Users/nata/Library/CloudStorage/OneDrive-Personal/CNC/VisionPro/World/mask_\(channel).png"
        )
        let mesh2D = try await meshGen.mesh(from: image)
        print("saved mask to \(maskURL)")

        print("✅  Generated mesh from \(imageName) [\(channel)]:")
        print("   • Vertices  : \(mesh2D.vertices.count)")
        print("   • Triangles : \(mesh2D.indices.count / 3)")
        print("   • Image size: \(mesh2D.imageSize.width) × \(mesh2D.imageSize.height)")

        // save black and white mask version for debugging

        return mesh2D

    } catch {
        print("❌  Mesh generation failed for \(imageName): \(error)")
        return nil
    }
}

@MainActor
func generateSplatModel(
    terrainName: String,
    terrainRotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0]),
    splatName imageName: String,
    channel: SplatMeshGenerator.Channel = .red,
    maxEdgeLength: CGFloat = 1.0,
    simplificationTolerance: CGFloat = 0.01,
    threshold: Float? = nil,
    invertMask: Bool? = nil,
    morphologyRadius: Int, // Radius for morphological operations, start with 2 ,
    interiorSpacingFactor: CGFloat
) async throws {
    // Generate the 2-D splat mesh ---------------------------------------------------
    if let mesh2D = await generateMeshFromImage(
        named: imageName,
        channel: channel,
        maxEdgeLength: maxEdgeLength,
        simplificationTolerance: simplificationTolerance,
        threshold: threshold,
        invertMask: invertMask,
        morphologyRadius: morphologyRadius,
        interiorSpacingFactor: interiorSpacingFactor
    ) {
        // 0️⃣ Load the terrain model -------------------------------------------------
        let myModelEntity: ModelEntity
        do {
            myModelEntity = try await ModelEntity(named: "terrainName")
            myModelEntity.scale = [1, 1, 1]
            print("Loaded model at pos \(myModelEntity.position), scale \(myModelEntity.scale)")

        } catch {
            print("❌  Error loading foothill.usdz: \(error)")
            return
        }

        // 1️⃣ Convert 2-D → 3-D using ObjMeshLoader ---------------------------------
        let meshLoader = MeshLoader(splatMesh2D: mesh2D, terrainModel: myModelEntity, terrainRotation: terrainRotation)

        // 2️⃣ (Optional) write the OBJ to disk --------------------------------------
        let outURL = URL(fileURLWithPath:
            "/Users/nata/Library/CloudStorage/OneDrive-Personal/CNC/VisionPro/World/splat.obj")
        try? meshLoader.writeOBJ(to: outURL)

        // 3️⃣ Create a RealityKit mesh entity for visual feedback -------------------
        let scale: Float = 0.01
        let height: Float = -330 - 10
        let zDistance: Float = -600

        let indices: [UInt32] = meshLoader.triangles.map { UInt32($0) }

        if let meshEntity = createMeshEntity(vertices: meshLoader.vertices,
                                             indices: indices,
                                             scale: 1.0, // already mapped → model space
                                             color: .blue)
        {
            meshEntity.name = "SplatMesh"
            // Position it above the terrain

            meshEntity.scale = SIMD3<Float>(scale, scale, scale)
            meshEntity.position.y += 1 * scale + height * scale
            meshEntity.position.z += zDistance * scale
            spaceOrigin.addChild(meshEntity)
        }

        // 4️⃣ Add terrain model to RealityKit
        myModelEntity.scale = SIMD3<Float>(scale, scale, scale)
        myModelEntity.position.y += height * scale
        myModelEntity.position.z += zDistance * scale

        // change rotation
        myModelEntity.orientation = terrainRotation

        spaceOrigin.addChild(myModelEntity)
    }
}
