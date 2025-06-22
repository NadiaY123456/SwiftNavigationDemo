//
//  ObjMeshLoader.swift
//  NavMeshDemo
//
//  Created by Miguel de Icaza on 8/22/23.
//

import Accelerate
import Foundation
import RealityKit
import simd
import SwiftNavigation

/// Very simple mesh loader; now supports three creation paths:
///    • init(file:)                ← from .obj file on disk
///    • init(verticesXZ:on:indices:)  ← from 2-D sample points + a ModelEntity
///    • init(vertices3D:indices:)  ← from full 3-D buffers already in memory
/// All initialisers end up with populated `vertices`, `triangles`, `normals`.
final class ObjMeshLoader {
    // MARK: - - Types & stored data -------------------------------------------------

    enum LoadError: Error {
        case invalidFormat
        case unsupportedFeature(String)
        var localizedDescription: String {
            switch self {
            case .invalidFormat: return "Invalid Format"
            case .unsupportedFeature(let s): return "Unsupported format feature: \(s)"
            }
        }
    }

    var scale = 1
    var vertices: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var triangles: [Int32] = []

    // MARK: - - Designated "empty" init --------------------------------------------

    init() { /* intentionally blank */ }

    // MARK: - - Path A — load from an OBJ file on disk -----------------------------

    convenience init(file: String) throws {
        self.init()
        try parseOBJ(String(contentsOfFile: file, encoding: .utf8))
    }

    // MARK: - - Path B — build from 2-D X-Z vertices + a RealityKit model ----------

    // Build 3D splat mesh that overlays the terrain
    convenience init(splatMesh2D: MeshResult2D, terrainModel: ModelEntity, terrainRotation: simd_quatf? = nil) {
        self.init()
        
        print("\n=== Building Splat Mesh Overlay ===")
        print("Splat vertices count: \(splatMesh2D.vertices.count)")
        print("Splat image size: \(splatMesh2D.imageSize.width) x \(splatMesh2D.imageSize.height)")
        
        if let rotation = terrainRotation {
            print("Applying terrain rotation: \(rotation)")
        }
        
        // 1. Map splat pixel coordinates to terrain's local space
        let terrainSpaceXZ = ObjMeshLoader.mapSplatPixelsToTerrainSpace(
            splatMesh2D.vertices,
            imageSize: splatMesh2D.imageSize,
            onto: terrainModel,
            rotation: terrainRotation
        )
        
        print("\nMapped splat vertices to terrain space")
        if terrainSpaceXZ.count > 0 {
            print("First mapped vertex: \(terrainSpaceXZ[0])")
            print("Last mapped vertex: \(terrainSpaceXZ[terrainSpaceXZ.count - 1])")
        }
        
        // 2. Sample terrain heights at each splat vertex position
        print("\nSampling terrain heights at \(terrainSpaceXZ.count) positions...")
        let heightSamples = ObjMeshLoader.sampleTerrainHeights(
            at: terrainSpaceXZ,
            on: terrainModel,
            rotation: terrainRotation
        )
        
        // Convert optional heights to default value of 0
        let heights = heightSamples.map { $0 ?? 0.0 }
        
        // Count valid heights
        let validHeightCount = heightSamples.compactMap { $0 }.count
        print("Valid heights sampled: \(validHeightCount) out of \(heightSamples.count)")
        
        if let minHeight = heights.min(), let maxHeight = heights.max() {
            print("Height range: \(minHeight) to \(maxHeight)")
        }
        
        // 3. Build the full 3D vertex buffer in terrain's local space
        self.vertices = zip(terrainSpaceXZ, heights).map { xz, y in
            [xz.x, y, xz.y]
        }
        
        print("\nBuilt \(vertices.count) 3D vertices for splat overlay")
        
        // 4. Use the triangle indices from the 2D splat mesh
        self.triangles = splatMesh2D.indices.map(Int32.init)
        print("Triangle indices count: \(triangles.count)")
        print("Triangle count: \(triangles.count / 3)")
        
        // 5. Rebuild normals for proper lighting
        rebuildNormals()
        
        print("=== Splat Mesh Overlay Complete ===\n")
    }

    // MARK: - - Path C — build from full 3-D buffers already in memory ------------

    convenience init(vertices3D: [SIMD3<Float>], indices: [UInt32]) {
        self.init()
        self.vertices = vertices3D
        self.triangles = indices.map { Int32($0) }
        rebuildNormals()
    }

    // MARK: - Helpers for 3D model ------------------------------------------------------------

    struct MeshBounds {
        let minX: Float
        let maxX: Float
        let minZ: Float
        let maxZ: Float
    }

    // Helper struct to cache LOCAL space vertices for the terrain
    struct TerrainMeshData {
        let vertices: [SIMD3<Float>]
        let xCoords: [Float]
        let yCoords: [Float]
        let zCoords: [Float]
        
        init(from terrainModel: ModelEntity, rotation: simd_quatf? = nil) {
            guard let mesh = terrainModel.model?.mesh else {
                self.vertices = []
                self.xCoords = []
                self.yCoords = []
                self.zCoords = []
                return
            }
            
            // Gather vertices - these are already in the terrain's local space
            let localVertices: [SIMD3<Float>] = mesh.contents.models.flatMap { meshModel in
                meshModel.parts.flatMap { part in
                    part.positions.elements
                }
            }
            
            guard !localVertices.isEmpty else {
                self.vertices = []
                self.xCoords = []
                self.yCoords = []
                self.zCoords = []
                return
            }
            
            // Apply rotation if provided
            let transformedVertices: [SIMD3<Float>]
            if let rotation = rotation {
                transformedVertices = localVertices.map { vertex in
                    let rotated = rotation.act(vertex)
                    return rotated
                }
            } else {
                transformedVertices = localVertices
            }
            
            // Extract coordinates for Accelerate
            let vertexCount = transformedVertices.count
            var xCoordsLocal = [Float](repeating: 0, count: vertexCount)
            var yCoordsLocal = [Float](repeating: 0, count: vertexCount)
            var zCoordsLocal = [Float](repeating: 0, count: vertexCount)
            
            for (i, v) in transformedVertices.enumerated() {
                xCoordsLocal[i] = v.x
                yCoordsLocal[i] = v.y
                zCoordsLocal[i] = v.z
            }
            
            self.vertices = transformedVertices
            self.xCoords = xCoordsLocal
            self.yCoords = yCoordsLocal
            self.zCoords = zCoordsLocal
        }
    }

    // Sample terrain height at given x,z position in local space
    static func sampleTerrainHeight(at localXZ: SIMD2<Float>, on terrainModel: ModelEntity, rotation: simd_quatf? = nil) -> Float? {
        let meshData = TerrainMeshData(from: terrainModel, rotation: rotation)
        
        guard !meshData.vertices.isEmpty else {
            return nil
        }
        
        // If rotation is provided, we need to rotate the query point to match the rotated terrain
        let queryXZ = localXZ
        
        let vertexCount = meshData.vertices.count
        var distances = [Float](repeating: 0, count: vertexCount)
        
        // Batch calculate squared distances
        var diffX = [Float](repeating: 0, count: vertexCount)
        var diffZ = [Float](repeating: 0, count: vertexCount)
        
        // X differences
        vDSP_vfill([queryXZ.x], &diffX, 1, vDSP_Length(vertexCount))
        vDSP_vsub(meshData.xCoords, 1, diffX, 1, &diffX, 1, vDSP_Length(vertexCount))
        vDSP_vsq(diffX, 1, &diffX, 1, vDSP_Length(vertexCount))
        
        // Z differences
        vDSP_vfill([queryXZ.y], &diffZ, 1, vDSP_Length(vertexCount))
        vDSP_vsub(meshData.zCoords, 1, diffZ, 1, &diffZ, 1, vDSP_Length(vertexCount))
        vDSP_vsq(diffZ, 1, &diffZ, 1, vDSP_Length(vertexCount))
        
        // Sum for total squared distance
        vDSP_vadd(diffX, 1, diffZ, 1, &distances, 1, vDSP_Length(vertexCount))
        
        // Find nearest
        var minDistance: Float = 0
        var minIndex: vDSP_Length = 0
        vDSP_minvi(distances, 1, &minDistance, &minIndex, vDSP_Length(vertexCount))
        
        return meshData.yCoords[Int(minIndex)]
    }

    // Batch sample multiple heights at once
    static func sampleTerrainHeights(at localXZPositions: [SIMD2<Float>], on terrainModel: ModelEntity, rotation: simd_quatf? = nil) -> [Float?] {
        let meshData = TerrainMeshData(from: terrainModel, rotation: rotation)
        
        guard !meshData.vertices.isEmpty else {
            return Array(repeating: nil, count: localXZPositions.count)
        }
        
        return localXZPositions.map { xz in
            // If rotation is provided, we need to rotate the query point to match the rotated terrain
            let queryXZ = xz
            
            let vertexCount = meshData.vertices.count
            var distances = [Float](repeating: 0, count: vertexCount)
            
            // Batch calculate squared distances
            var diffX = [Float](repeating: 0, count: vertexCount)
            var diffZ = [Float](repeating: 0, count: vertexCount)
            
            // X differences
            vDSP_vfill([queryXZ.x], &diffX, 1, vDSP_Length(vertexCount))
            vDSP_vsub(meshData.xCoords, 1, diffX, 1, &diffX, 1, vDSP_Length(vertexCount))
            vDSP_vsq(diffX, 1, &diffX, 1, vDSP_Length(vertexCount))
            
            // Z differences
            vDSP_vfill([queryXZ.y], &diffZ, 1, vDSP_Length(vertexCount))
            vDSP_vsub(meshData.zCoords, 1, diffZ, 1, &diffZ, 1, vDSP_Length(vertexCount))
            vDSP_vsq(diffZ, 1, &diffZ, 1, vDSP_Length(vertexCount))
            
            // Sum for total squared distance
            vDSP_vadd(diffX, 1, diffZ, 1, &distances, 1, vDSP_Length(vertexCount))
            
            // Find nearest
            var minDistance: Float = 0
            var minIndex: vDSP_Length = 0
            vDSP_minvi(distances, 1, &minDistance, &minIndex, vDSP_Length(vertexCount))
            
            return meshData.yCoords[Int(minIndex)]
        }
    }

    // Map pixel coordinates from splat map to terrain's local space
    static func mapSplatPixelsToTerrainSpace(_ pixelVerts: [SIMD2<Float>],
                                             imageSize: CGSize,
                                             onto terrainModel: ModelEntity,
                                             rotation: simd_quatf? = nil) -> [SIMD2<Float>]
    {
        // Get visual bounds
        let visualBounds = terrainModel.visualBounds(relativeTo: terrainModel)
        var visualMin = visualBounds.min
        var visualExtents = visualBounds.extents
        
        // If rotation is provided, we need to transform the bounds
        if let rotation = rotation {
            // Get all 8 corners of the bounding box
            let corners = [
                SIMD3<Float>(visualMin.x, visualMin.y, visualMin.z),
                SIMD3<Float>(visualMin.x + visualExtents.x, visualMin.y, visualMin.z),
                SIMD3<Float>(visualMin.x, visualMin.y + visualExtents.y, visualMin.z),
                SIMD3<Float>(visualMin.x + visualExtents.x, visualMin.y + visualExtents.y, visualMin.z),
                SIMD3<Float>(visualMin.x, visualMin.y, visualMin.z + visualExtents.z),
                SIMD3<Float>(visualMin.x + visualExtents.x, visualMin.y, visualMin.z + visualExtents.z),
                SIMD3<Float>(visualMin.x, visualMin.y + visualExtents.y, visualMin.z + visualExtents.z),
                SIMD3<Float>(visualMin.x + visualExtents.x, visualMin.y + visualExtents.y, visualMin.z + visualExtents.z)
            ]
            
            // Rotate all corners
            let rotatedCorners = corners.map { rotation.act($0) }
            
            // Find new bounds from rotated corners
            var newMin = rotatedCorners[0]
            var newMax = rotatedCorners[0]
            
            for corner in rotatedCorners {
                newMin.x = min(newMin.x, corner.x)
                newMin.y = min(newMin.y, corner.y)
                newMin.z = min(newMin.z, corner.z)
                newMax.x = max(newMax.x, corner.x)
                newMax.y = max(newMax.y, corner.y)
                newMax.z = max(newMax.z, corner.z)
            }
            
            visualMin = newMin
            visualExtents = newMax - newMin
        }
        
        print("\nTerrain bounds - X: [\(visualMin.x), \(visualMin.x + visualExtents.x)]")
        print("Terrain bounds - Z: [\(visualMin.z), \(visualMin.z + visualExtents.z)]")
        
        // Scale factors to stretch splat image to terrain dimensions
        let scaleX = visualExtents.x / Float(imageSize.width)
        let scaleZ = visualExtents.z / Float(imageSize.height)
        
        print("Scale factors - X: \(scaleX), Z: \(scaleZ)")
        
        return pixelVerts.map { pixelCoord in
            // Map pixel coordinates to terrain's local space
            // Note: Y is already flipped in SplatMeshGenerator to match RealityKit
            SIMD2<Float>(
                visualMin.x + pixelCoord.x * scaleX,
                visualMin.z + pixelCoord.y * scaleZ
            )
        }
    }
    
    // MARK: - - Rebuild normals ----------------------------------------------------
    
    private func rebuildNormals() {
        normals.removeAll(keepingCapacity: true)
        for i in stride(from: 0, to: triangles.count, by: 3) {
            let v0 = triangles[i]
            let v1 = triangles[i + 1]
            let v2 = triangles[i + 2]

            let e0 = vertices[Int(v1)] - vertices[Int(v0)] //Thread 1: Fatal error: Index out of range
            let e1 = vertices[Int(v2)] - vertices[Int(v0)]
            let n = cross(e0, e1)
            let len = simd_length(n)
            normals.append(len > 0 ? n / len : n)
        }
    }

    // MARK: - Shared OBJ text parser (used by both `init(file:)` and `init(rawOBJ:)`).

    private func parseOBJ(_ rawOBJ: String) throws {
        let lines = rawOBJ
            .replacingOccurrences(of: "\r", with: "")
            .split(separator: "\n")

        for line in lines {
            switch line.first {
            case "v": // vertex
                if line.starts(with: "v ") {
                    let p = line.split(separator: " ")
                    guard p.count >= 4 else { throw LoadError.invalidFormat }
                    vertices.append([Float(p[1]) ?? 0,
                                     Float(p[2]) ?? 0,
                                     Float(p[3]) ?? 0])
                }

            case "f": // face (as polygon or triangle fan)
                let vCount = Int32(vertices.count)
                let parts = line.split(whereSeparator: { $0.isWhitespace }).dropFirst()
                let faceIdxs = parts.map { part -> Int32 in
                    if let slash = part.firstIndex(of: "/") {
                        return Int32(part[..<slash]) ?? 0
                    } else {
                        return Int32(part) ?? 0
                    }
                }.map { $0 < 0 ? vCount : $0 - 1 } // .obj negative indices

                guard faceIdxs.count > 2 else { break }
                let a = faceIdxs[0]
                for i in 2..<faceIdxs.count {
                    let b = faceIdxs[i - 1]
                    let c = faceIdxs[i]
                    guard (0..<vCount).contains(a),
                          (0..<vCount).contains(b),
                          (0..<vCount).contains(c) else { continue }
                    triangles.append(contentsOf: [a, b, c])
                }

            case "#", "m", "u", "o", "g": break // ignore comments / mtllib…
            default: break
            }
        }
        rebuildNormals()
    }

    // MARK: - - Public: write to disk ---------------------------------------------

    /// Produces a vanilla ASCII OBJ file (v & f only).
    func writeOBJ(to url: URL) throws {
        var obj = ""
        for v in vertices {
            obj += String(format: "v %.6f %.6f %.6f\n", v.x, v.y, v.z)
        }
        for i in stride(from: 0, to: triangles.count, by: 3) {
            obj += "f \(triangles[i] + 1) \(triangles[i + 1] + 1) \(triangles[i + 2] + 1)\n"
        }
        try obj.write(to: url, atomically: true, encoding: .utf8)
    }
}

#if false

func testCrowd() throws {
    let data = try ObjMeshLoader(file: "/Users/nata/GitHub/Practicing/recastnavigation/RecastDemo/Bin/Meshes/dungeon.obj")
    let config = NavMeshBuilder.Config(partitionStyle: .monotone)
    let builder = try NavMeshBuilder(vertices: data.vertices, triangles: data.triangles, config: config)
    let navigator = try builder.makeNavMesh(agentHeight: 1, agentRadius: 0.3, agentMaxClimb: 20)
    let query = try navigator.makeQuery()

    let end = try query.findRandomPoint(randomFunction: fakeRandom).get()
    print("Target is: \(end)")

    let crowd = try navigator.makeCrowd(maxAgents: 16, agentRadius: 0.3)
    var agents: [CrowdAgent] = []
    for _ in 0..<4 {
        let agentStart = try query.findRandomPoint(randomFunction: fakeRandom).get()
        guard let agent = crowd.addAgent(agentStart.point3) else { continue }
        agents.append(agent)
        agent.requestMove(target: end)
    }
    for x in stride(from: 0.0, to: 3.0, by: 0.01) {
        crowd.update(dt: Float(x))
        for x in 0..<agents.count {
            print("\(x): \(agents[x].position)")
        }
    }
}
#endif

// MARK: - Depth-first walk over any entity tree -------------------------------

extension Entity {
    /// Runs `body(self)` and then depth-first on every child.
    func visit(_ body: (Entity) -> Void) {
        body(self)
        children.forEach { $0.visit(body) }
    }
}

// MARK: - Exact X-Z bounds pulled straight from vertex buffers ---------------

extension ModelEntity {
    /// Precise min / max in X-Z for *all* render meshes in **local** space.
    func exactLocalXZBounds() -> (min: SIMD2<Float>, max: SIMD2<Float>) {
        var minX = Float.infinity, maxX = -Float.infinity
        var minZ = Float.infinity, maxZ = -Float.infinity

        visit { entity in
            guard
                let modelComp = entity.components[ModelComponent.self]
            else { return }

            let bbox = modelComp.mesh.bounds
            minX = min(minX, bbox.min.x)
            maxX = max(maxX, bbox.max.x)
            minZ = min(minZ, bbox.min.z)
            maxZ = max(maxZ, bbox.max.z)
        }
        return (SIMD2<Float>(minX, minZ), SIMD2<Float>(maxX, maxZ))
    }
}
