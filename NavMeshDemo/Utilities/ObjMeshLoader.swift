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

    // MARK: - - Designated “empty” init --------------------------------------------

    init() { /* intentionally blank */ }

    // MARK: - - Path A — load from an OBJ file on disk -----------------------------

    convenience init(file: String) throws {
        self.init()
        try parseOBJ(String(contentsOfFile: file))
    }

    // MARK: - - Path B — build from 2-D X-Z vertices + a RealityKit model ----------

    // Build 3D splat mesh that overlays the terrain
    convenience init(splatMesh2D: MeshResult2D, terrainModel: ModelEntity) {
        self.init()
        
        print("\n=== Building Splat Mesh Overlay ===")
        print("Splat vertices count: \(splatMesh2D.vertices.count)")
        print("Splat image size: \(splatMesh2D.imageSize.width) x \(splatMesh2D.imageSize.height)")
        
        // 1. Map splat pixel coordinates to terrain's local space
        let terrainSpaceXZ = ObjMeshLoader.mapSplatPixelsToTerrainSpace(
            splatMesh2D.vertices,
            imageSize: splatMesh2D.imageSize,
            onto: terrainModel
        )
        
        print("\nMapped splat vertices to terrain space")
        if terrainSpaceXZ.count > 0 {
            print("First mapped vertex: \(terrainSpaceXZ[0])")
            print("Last mapped vertex: \(terrainSpaceXZ[terrainSpaceXZ.count - 1])")
        }
        
        // 2. Sample terrain heights at each splat vertex position
        print("\nSampling terrain heights at \(terrainSpaceXZ.count) positions...")
        let heightSamples = ObjMeshLoader.sampleTerrainHeights(at: terrainSpaceXZ, on: terrainModel)
        
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
        
        init(from terrainModel: ModelEntity) {
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
            
            // Extract coordinates for Accelerate
            let vertexCount = localVertices.count
            var xCoordsLocal = [Float](repeating: 0, count: vertexCount)
            var yCoordsLocal = [Float](repeating: 0, count: vertexCount)
            var zCoordsLocal = [Float](repeating: 0, count: vertexCount)
            
            for (i, v) in localVertices.enumerated() {
                xCoordsLocal[i] = v.x
                yCoordsLocal[i] = v.y
                zCoordsLocal[i] = v.z
            }
            
            self.vertices = localVertices
            self.xCoords = xCoordsLocal
            self.yCoords = yCoordsLocal
            self.zCoords = zCoordsLocal
        }
    }

    // Get terrain bounds in local space
    static func getTerrainBoundsInLocalSpace(for terrainModel: ModelEntity) -> MeshBounds? {
        let meshData = TerrainMeshData(from: terrainModel)
        
        guard !meshData.vertices.isEmpty else {
            return nil
        }
        
        let vertexCount = meshData.vertices.count
        
        // Calculate local-space bounds
        var minX: Float = 0, maxX: Float = 0
        var minZ: Float = 0, maxZ: Float = 0
        
        vDSP_minv(meshData.xCoords, 1, &minX, vDSP_Length(vertexCount))
        vDSP_maxv(meshData.xCoords, 1, &maxX, vDSP_Length(vertexCount))
        vDSP_minv(meshData.zCoords, 1, &minZ, vDSP_Length(vertexCount))
        vDSP_maxv(meshData.zCoords, 1, &maxZ, vDSP_Length(vertexCount))
        
        return MeshBounds(minX: minX, maxX: maxX, minZ: minZ, maxZ: maxZ)
    }

    // Sample terrain height at given x,z position in local space
    static func sampleTerrainHeight(at localXZ: SIMD2<Float>, on terrainModel: ModelEntity) -> Float? {
        let meshData = TerrainMeshData(from: terrainModel)
        
        guard !meshData.vertices.isEmpty else {
            return nil
        }
        
        let vertexCount = meshData.vertices.count
        var distances = [Float](repeating: 0, count: vertexCount)
        
        // Batch calculate squared distances
        var diffX = [Float](repeating: 0, count: vertexCount)
        var diffZ = [Float](repeating: 0, count: vertexCount)
        
        // X differences
        vDSP_vfill([localXZ.x], &diffX, 1, vDSP_Length(vertexCount))
        vDSP_vsub(meshData.xCoords, 1, diffX, 1, &diffX, 1, vDSP_Length(vertexCount))
        vDSP_vsq(diffX, 1, &diffX, 1, vDSP_Length(vertexCount))
        
        // Z differences
        vDSP_vfill([localXZ.y], &diffZ, 1, vDSP_Length(vertexCount))
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
    static func sampleTerrainHeights(at localXZPositions: [SIMD2<Float>], on terrainModel: ModelEntity) -> [Float?] {
        let meshData = TerrainMeshData(from: terrainModel)
        
        guard !meshData.vertices.isEmpty else {
            return Array(repeating: nil, count: localXZPositions.count)
        }
        
        return localXZPositions.map { xz in
            let vertexCount = meshData.vertices.count
            var distances = [Float](repeating: 0, count: vertexCount)
            
            // Batch calculate squared distances
            var diffX = [Float](repeating: 0, count: vertexCount)
            var diffZ = [Float](repeating: 0, count: vertexCount)
            
            // X differences
            vDSP_vfill([xz.x], &diffX, 1, vDSP_Length(vertexCount))
            vDSP_vsub(meshData.xCoords, 1, diffX, 1, &diffX, 1, vDSP_Length(vertexCount))
            vDSP_vsq(diffX, 1, &diffX, 1, vDSP_Length(vertexCount))
            
            // Z differences
            vDSP_vfill([xz.y], &diffZ, 1, vDSP_Length(vertexCount))
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
                                             onto terrainModel: ModelEntity) -> [SIMD2<Float>]
    {
        // Method 1: RealityKit visual bounds
        let visualBounds = terrainModel.visualBounds(relativeTo: terrainModel)
        let visualMin = visualBounds.min
        let visualExtents = visualBounds.extents
        
        // Method 2: Calculate actual mesh bounds in local space
        var meshBounds: MeshBounds?
        if let calculatedBounds = getTerrainBoundsInLocalSpace(for: terrainModel) {
            meshBounds = calculatedBounds
            
            // Print comparison
            print("\n=== Terrain Bounds Comparison ===")
            print("Visual Bounds (RealityKit):")
            print("  Min: (\(visualMin.x), \(visualMin.z))")
            print("  Max: (\(visualMin.x + visualExtents.x), \(visualMin.z + visualExtents.z))")
            print("  Extents: (\(visualExtents.x), \(visualExtents.z))")
            
            print("\nMesh Bounds (Calculated from vertices):")
            print("  Min: (\(calculatedBounds.minX), \(calculatedBounds.minZ))")
            print("  Max: (\(calculatedBounds.maxX), \(calculatedBounds.maxZ))")
            print("  Extents: (\(calculatedBounds.maxX - calculatedBounds.minX), \(calculatedBounds.maxZ - calculatedBounds.minZ))")
            
            print("\nDifferences:")
            print("  Min X diff: \(abs(visualMin.x - calculatedBounds.minX))")
            print("  Min Z diff: \(abs(visualMin.z - calculatedBounds.minZ))")
            print("  Extent X diff: \(abs(visualExtents.x - (calculatedBounds.maxX - calculatedBounds.minX)))")
            print("  Extent Z diff: \(abs(visualExtents.z - (calculatedBounds.maxZ - calculatedBounds.minZ)))")
            print("========================\n")
        } else {
            print("Warning: Could not calculate mesh bounds from vertices")
        }
        
        // Use calculated mesh bounds for more accurate mapping
        let minX: Float
        let minZ: Float
        let extentX: Float
        let extentZ: Float
        
        if let bounds = meshBounds {
            minX = bounds.minX
            minZ = bounds.minZ
            extentX = bounds.maxX - bounds.minX
            extentZ = bounds.maxZ - bounds.minZ
            print("Using calculated mesh bounds for mapping splat to terrain")
        } else {
            // Fallback to visual bounds
            minX = visualMin.x
            minZ = visualMin.z
            extentX = visualExtents.x
            extentZ = visualExtents.z
            print("Using visual bounds for mapping (fallback)")
        }
        
        // Scale factors to stretch splat image to terrain dimensions
        let scaleX = extentX / Float(imageSize.width)
        let scaleZ = extentZ / Float(imageSize.height)
        
        print("Scale factors - X: \(scaleX), Z: \(scaleZ)")
        
        return pixelVerts.map { pixelCoord in
            // Map pixel coordinates to terrain's local space
            // Note: Image Y goes down, but Z typically goes forward, so we flip Y
            SIMD2<Float>(
                minX + pixelCoord.x * scaleX,
                minZ + (Float(imageSize.height) - pixelCoord.y) * scaleZ
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

            let e0 = vertices[Int(v1)] - vertices[Int(v0)]
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
