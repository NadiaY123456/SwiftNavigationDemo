////
////  MeshLoader.swift
////  NavMeshDemo
////
////  Created by Nadia Yilmaz on 6/22/25.
////
//
//import Accelerate
//import Foundation
//import RealityKit
//import simd
//import SwiftNavigation
//
///// Mesh loader supporting multiple creation paths for navigation mesh generation.
///// Supports loading from OBJ files, 2D sample points, and 3D vertex buffers.
//final class MeshLoader {
//    // MARK: - Types & Properties
//    
//    /// Errors that can occur during mesh loading operations
//    enum LoadError: Error {
//        case invalidFormat
//        case unsupportedFeature(String)
//        var localizedDescription: String {
//            switch self {
//            case .invalidFormat: return "Invalid Format"
//            case .unsupportedFeature(let s): return "Unsupported format feature: \(s)"
//            }
//        }
//    }
//    
//    /// Scale factor for the mesh
//    var scale = 1
//    /// 3D vertex positions
//    var vertices: [SIMD3<Float>] = []
//    /// Per-triangle normals
//    var normals: [SIMD3<Float>] = []
//    /// Triangle indices (3 per triangle)
//    var triangles: [Int32] = []
//    
//    // MARK: - Initialization
//    
//    /// Creates an empty mesh loader
//    init() { /* intentionally blank */ }
//    
//    // MARK: - Path A: Load from OBJ File
//    
//    /// Loads mesh data from an OBJ file on disk
//    convenience init(file: String) throws {
//        self.init()
//        try parseOBJ(String(contentsOfFile: file, encoding: .utf8))
//    }
//    
//    // MARK: - Path B: Build from 2D Vertices + RealityKit Model
//    
//    /// Creates a 3D mesh by projecting 2D splat vertices onto a RealityKit terrain model
//    convenience init(splatMesh2D: MeshResult2D, terrainModel: ModelEntity, terrainRotation: simd_quatf? = nil) {
//        self.init()
//        
//        print("\n=== Building Splat Mesh Overlay ===")
//        print("Splat vertices count: \(splatMesh2D.vertices.count)")
//        print("Splat image size: \(splatMesh2D.imageSize.width) x \(splatMesh2D.imageSize.height)")
//        
//        if let rotation = terrainRotation {
//            print("Applying terrain rotation: \(rotation)")
//        }
//        
//        // Map splat pixels to terrain space
//        let terrainSpaceXZ = MeshLoader.mapSplatPixelsToTerrainSpace(
//            splatMesh2D.vertices,
//            imageSize: splatMesh2D.imageSize,
//            onto: terrainModel,
//            rotation: terrainRotation
//        )
//        
//        print("\nMapped splat vertices to terrain space")
//        if terrainSpaceXZ.count > 0 {
//            print("First mapped vertex: \(terrainSpaceXZ[0])")
//            print("Last mapped vertex: \(terrainSpaceXZ[terrainSpaceXZ.count - 1])")
//        }
//        
//        // Sample terrain heights
//        print("\nSampling terrain heights at \(terrainSpaceXZ.count) positions...")
//        let heightSamples = MeshLoader.sampleTerrainHeights(
//            at: terrainSpaceXZ,
//            on: terrainModel,
//            rotation: terrainRotation
//        )
//        
//        // Convert optional heights to default value of 0
//        let heights = heightSamples.map { $0 ?? 0.0 }
//        
//        // Count valid heights
//        let validHeightCount = heightSamples.compactMap { $0 }.count
//        print("Valid heights sampled: \(validHeightCount) out of \(heightSamples.count)")
//        
//        if let minHeight = heights.min(), let maxHeight = heights.max() {
//            print("Height range: \(minHeight) to \(maxHeight)")
//        }
//        
//        // Build 3D vertices
//        self.vertices = zip(terrainSpaceXZ, heights).map { xz, y in
//            [xz.x, y, xz.y]
//        }
//        
//        print("\nBuilt \(vertices.count) 3D vertices for splat overlay")
//        
//        // Copy triangle indices
//        self.triangles = splatMesh2D.indices.map(Int32.init)
//        print("Triangle indices count: \(triangles.count)")
//        print("Triangle count: \(triangles.count / 3)")
//        
//        // Generate normals
//        rebuildNormals()
//        
//        print("=== Splat Mesh Overlay Complete ===\n")
//    }
//    
//    // MARK: - Path C: Build from 3D Vertices
//    
//    /// Creates mesh from pre-existing 3D vertex and index buffers
//    convenience init(vertices3D: [SIMD3<Float>], indices: [UInt32]) {
//        self.init()
//        self.vertices = vertices3D
//        self.triangles = indices.map { Int32($0) }
//        rebuildNormals()
//    }
//    
//    // MARK: - Path D: Build from 2D Vertices + OBJ Terrain
//    
//    /// Creates a 3D mesh by projecting 2D splat vertices onto terrain loaded from an OBJ file
//    convenience init(splatMesh2D: MeshResult2D, terrainOBJPath: String, terrainScale: Float = 1.0) throws {
//        self.init()
//        
//        print("\n=== Building Splat Mesh Overlay from OBJ Terrain ===")
//        print("Splat vertices count: \(splatMesh2D.vertices.count)")
//        print("Splat image size: \(splatMesh2D.imageSize.width) x \(splatMesh2D.imageSize.height)")
//        print("Loading terrain from: \(terrainOBJPath)")
//        
//        // Load terrain mesh
//        let terrainMesh = try MeshLoader(file: terrainOBJPath)
//        print("Terrain vertices: \(terrainMesh.vertices.count)")
//        
//        // Get terrain bounds
//        let bounds = terrainMesh.computeBounds()
//        print("\nTerrain bounds - X: [\(bounds.minX), \(bounds.maxX)]")
//        print("Terrain bounds - Z: [\(bounds.minZ), \(bounds.maxZ)]")
//        
//        // Map splat pixels to terrain space
//        let terrainSpaceXZ = MeshLoader.mapSplatPixelsToOBJTerrainSpace(
//            splatMesh2D.vertices,
//            imageSize: splatMesh2D.imageSize,
//            terrainBounds: bounds,
//            scale: terrainScale
//        )
//        
//        print("\nMapped splat vertices to terrain space")
//        if terrainSpaceXZ.count > 0 {
//            print("First mapped vertex: \(terrainSpaceXZ[0])")
//            print("Last mapped vertex: \(terrainSpaceXZ[terrainSpaceXZ.count - 1])")
//        }
//        
//        // Sample terrain heights
//        print("\nSampling terrain heights at \(terrainSpaceXZ.count) positions...")
//        let heights = MeshLoader.sampleOBJTerrainHeights(
//            at: terrainSpaceXZ,
//            terrainVertices: terrainMesh.vertices,
//            scale: terrainScale
//        )
//        
//        // Count valid heights
//        if let minHeight = heights.min(), let maxHeight = heights.max() {
//            print("Height range: \(minHeight) to \(maxHeight)")
//        }
//        
//        // Build 3D vertices
//        self.vertices = zip(terrainSpaceXZ, heights).map { xz, y in
//            [xz.x, y, xz.y]
//        }
//        
//        print("\nBuilt \(vertices.count) 3D vertices for splat overlay")
//        
//        // Copy triangle indices
//        self.triangles = splatMesh2D.indices.map(Int32.init)
//        print("Triangle indices count: \(triangles.count)")
//        print("Triangle count: \(triangles.count / 3)")
//        
//        // Generate normals
//        rebuildNormals()
//        
//        print("=== Splat Mesh Overlay Complete ===\n")
//    }
//    
//    // MARK: - OBJ Terrain Helpers
//    
//    /// Mesh bounds for terrain calculations
//    struct MeshBounds {
//        let minX: Float
//        let maxX: Float
//        let minZ: Float
//        let maxZ: Float
//    }
//    
//    /// Computes the X-Z bounds of the current mesh
//    func computeBounds() -> MeshBounds {
//        guard !vertices.isEmpty else {
//            return MeshBounds(minX: 0, maxX: 0, minZ: 0, maxZ: 0)
//        }
//        
//        var minX = Float.infinity
//        var maxX = -Float.infinity
//        var minZ = Float.infinity
//        var maxZ = -Float.infinity
//        
//        for v in vertices {
//            minX = min(minX, v.x)
//            maxX = max(maxX, v.x)
//            minZ = min(minZ, v.z)
//            maxZ = max(maxZ, v.z)
//        }
//        
//        return MeshBounds(minX: minX, maxX: maxX, minZ: minZ, maxZ: maxZ)
//    }
//    
//    /// Maps pixel coordinates to OBJ terrain space
//    static func mapSplatPixelsToOBJTerrainSpace(_ pixelVerts: [SIMD2<Float>],
//                                                imageSize: CGSize,
//                                                terrainBounds: MeshBounds,
//                                                scale: Float) -> [SIMD2<Float>]
//    {
//        // Calculate terrain dimensions
//        let terrainWidth = (terrainBounds.maxX - terrainBounds.minX) * scale
//        let terrainDepth = (terrainBounds.maxZ - terrainBounds.minZ) * scale
//        
//        // Scale factors
//        let scaleX = terrainWidth / Float(imageSize.width)
//        let scaleZ = terrainDepth / Float(imageSize.height)
//        
//        print("Scale factors - X: \(scaleX), Z: \(scaleZ)")
//        
//        return pixelVerts.map { pixelCoord in
//            SIMD2<Float>(
//                terrainBounds.minX * scale + pixelCoord.x * scaleX,
//                terrainBounds.minZ * scale + pixelCoord.y * scaleZ
//            )
//        }
//    }
//    
//    /// Samples terrain heights from OBJ vertices using nearest neighbor
//    static func sampleOBJTerrainHeights(at localXZPositions: [SIMD2<Float>],
//                                       terrainVertices: [SIMD3<Float>],
//                                       scale: Float) -> [Float]
//    {
//        guard !terrainVertices.isEmpty else {
//            return Array(repeating: 0, count: localXZPositions.count)
//        }
//        
//        // Scale terrain vertices
//        let scaledVertices = terrainVertices.map { $0 * scale }
//        
//        // Extract coordinates for Accelerate
//        let vertexCount = scaledVertices.count
//        let xCoords = scaledVertices.map { $0.x }
//        let yCoords = scaledVertices.map { $0.y }
//        let zCoords = scaledVertices.map { $0.z }
//        
//        return localXZPositions.map { xz in
//            var distances = [Float](repeating: 0, count: vertexCount)
//            
//            // Batch calculate squared distances
//            var diffX = [Float](repeating: 0, count: vertexCount)
//            var diffZ = [Float](repeating: 0, count: vertexCount)
//            
//            // X differences
//            vDSP_vfill([xz.x], &diffX, 1, vDSP_Length(vertexCount))
//            vDSP_vsub(xCoords, 1, diffX, 1, &diffX, 1, vDSP_Length(vertexCount))
//            vDSP_vsq(diffX, 1, &diffX, 1, vDSP_Length(vertexCount))
//            
//            // Z differences
//            vDSP_vfill([xz.y], &diffZ, 1, vDSP_Length(vertexCount))
//            vDSP_vsub(zCoords, 1, diffZ, 1, &diffZ, 1, vDSP_Length(vertexCount))
//            vDSP_vsq(diffZ, 1, &diffZ, 1, vDSP_Length(vertexCount))
//            
//            // Sum for total squared distance
//            vDSP_vadd(diffX, 1, diffZ, 1, &distances, 1, vDSP_Length(vertexCount))
//            
//            // Find nearest
//            var minDistance: Float = 0
//            var minIndex: vDSP_Length = 0
//            vDSP_minvi(distances, 1, &minDistance, &minIndex, vDSP_Length(vertexCount))
//            
//            return yCoords[Int(minIndex)]
//        }
//    }
//    
//    // MARK: - RealityKit Model Helpers
//    
//    /// Cached terrain mesh data for efficient height sampling
//    struct TerrainMeshData {
//        let vertices: [SIMD3<Float>]
//        let xCoords: [Float]
//        let yCoords: [Float]
//        let zCoords: [Float]
//        
//        /// Extracts and caches terrain vertex data from a ModelEntity
//        init(from terrainModel: ModelEntity, rotation: simd_quatf? = nil) {
//            guard let mesh = terrainModel.model?.mesh else {
//                self.vertices = []
//                self.xCoords = []
//                self.yCoords = []
//                self.zCoords = []
//                return
//            }
//            
//            // Gather vertices in local space
//            let localVertices: [SIMD3<Float>] = mesh.contents.models.flatMap { meshModel in
//                meshModel.parts.flatMap { part in
//                    part.positions.elements
//                }
//            }
//            
//            guard !localVertices.isEmpty else {
//                self.vertices = []
//                self.xCoords = []
//                self.yCoords = []
//                self.zCoords = []
//                return
//            }
//            
//            // Apply rotation if provided
//            let transformedVertices: [SIMD3<Float>]
//            if let rotation = rotation {
//                transformedVertices = localVertices.map { vertex in
//                    rotation.act(vertex)
//                }
//            } else {
//                transformedVertices = localVertices
//            }
//            
//            // Extract coordinates for Accelerate
//            let vertexCount = transformedVertices.count
//            var xCoordsLocal = [Float](repeating: 0, count: vertexCount)
//            var yCoordsLocal = [Float](repeating: 0, count: vertexCount)
//            var zCoordsLocal = [Float](repeating: 0, count: vertexCount)
//            
//            for (i, v) in transformedVertices.enumerated() {
//                xCoordsLocal[i] = v.x
//                yCoordsLocal[i] = v.y
//                zCoordsLocal[i] = v.z
//            }
//            
//            self.vertices = transformedVertices
//            self.xCoords = xCoordsLocal
//            self.yCoords = yCoordsLocal
//            self.zCoords = zCoordsLocal
//        }
//    }
//    
//    /// Samples a single terrain height at given X-Z position
//    static func sampleTerrainHeight(at localXZ: SIMD2<Float>, on terrainModel: ModelEntity, rotation: simd_quatf? = nil) -> Float? {
//        let meshData = TerrainMeshData(from: terrainModel, rotation: rotation)
//        
//        guard !meshData.vertices.isEmpty else {
//            return nil
//        }
//        
//        let vertexCount = meshData.vertices.count
//        var distances = [Float](repeating: 0, count: vertexCount)
//        
//        // Batch calculate squared distances
//        var diffX = [Float](repeating: 0, count: vertexCount)
//        var diffZ = [Float](repeating: 0, count: vertexCount)
//        
//        // X differences
//        vDSP_vfill([localXZ.x], &diffX, 1, vDSP_Length(vertexCount))
//        vDSP_vsub(meshData.xCoords, 1, diffX, 1, &diffX, 1, vDSP_Length(vertexCount))
//        vDSP_vsq(diffX, 1, &diffX, 1, vDSP_Length(vertexCount))
//        
//        // Z differences
//        vDSP_vfill([localXZ.y], &diffZ, 1, vDSP_Length(vertexCount))
//        vDSP_vsub(meshData.zCoords, 1, diffZ, 1, &diffZ, 1, vDSP_Length(vertexCount))
//        vDSP_vsq(diffZ, 1, &diffZ, 1, vDSP_Length(vertexCount))
//        
//        // Sum for total squared distance
//        vDSP_vadd(diffX, 1, diffZ, 1, &distances, 1, vDSP_Length(vertexCount))
//        
//        // Find nearest
//        var minDistance: Float = 0
//        var minIndex: vDSP_Length = 0
//        vDSP_minvi(distances, 1, &minDistance, &minIndex, vDSP_Length(vertexCount))
//        
//        return meshData.yCoords[Int(minIndex)]
//    }
//    
//    /// Batch samples multiple terrain heights
//    static func sampleTerrainHeights(at localXZPositions: [SIMD2<Float>], on terrainModel: ModelEntity, rotation: simd_quatf? = nil) -> [Float?] {
//        let meshData = TerrainMeshData(from: terrainModel, rotation: rotation)
//        
//        guard !meshData.vertices.isEmpty else {
//            return Array(repeating: nil, count: localXZPositions.count)
//        }
//        
//        return localXZPositions.map { xz in
//            let vertexCount = meshData.vertices.count
//            var distances = [Float](repeating: 0, count: vertexCount)
//            
//            // Batch calculate squared distances
//            var diffX = [Float](repeating: 0, count: vertexCount)
//            var diffZ = [Float](repeating: 0, count: vertexCount)
//            
//            // X differences
//            vDSP_vfill([xz.x], &diffX, 1, vDSP_Length(vertexCount))
//            vDSP_vsub(meshData.xCoords, 1, diffX, 1, &diffX, 1, vDSP_Length(vertexCount))
//            vDSP_vsq(diffX, 1, &diffX, 1, vDSP_Length(vertexCount))
//            
//            // Z differences
//            vDSP_vfill([xz.y], &diffZ, 1, vDSP_Length(vertexCount))
//            vDSP_vsub(meshData.zCoords, 1, diffZ, 1, &diffZ, 1, vDSP_Length(vertexCount))
//            vDSP_vsq(diffZ, 1, &diffZ, 1, vDSP_Length(vertexCount))
//            
//            // Sum for total squared distance
//            vDSP_vadd(diffX, 1, diffZ, 1, &distances, 1, vDSP_Length(vertexCount))
//            
//            // Find nearest
//            var minDistance: Float = 0
//            var minIndex: vDSP_Length = 0
//            vDSP_minvi(distances, 1, &minDistance, &minIndex, vDSP_Length(vertexCount))
//            
//            return meshData.yCoords[Int(minIndex)]
//        }
//    }
//    
//    /// Maps pixel coordinates from splat map to terrain's local space
//    static func mapSplatPixelsToTerrainSpace(_ pixelVerts: [SIMD2<Float>],
//                                             imageSize: CGSize,
//                                             onto terrainModel: ModelEntity,
//                                             rotation: simd_quatf? = nil) -> [SIMD2<Float>]
//    {
//        // Get visual bounds
//        let visualBounds = terrainModel.visualBounds(relativeTo: terrainModel)
//        var visualMin = visualBounds.min
//        var visualExtents = visualBounds.extents
//        
//        // Apply rotation to bounds if needed
//        if let rotation = rotation {
//            // Get all 8 corners of the bounding box
//            let corners = [
//                SIMD3<Float>(visualMin.x, visualMin.y, visualMin.z),
//                SIMD3<Float>(visualMin.x + visualExtents.x, visualMin.y, visualMin.z),
//                SIMD3<Float>(visualMin.x, visualMin.y + visualExtents.y, visualMin.z),
//                SIMD3<Float>(visualMin.x + visualExtents.x, visualMin.y + visualExtents.y, visualMin.z),
//                SIMD3<Float>(visualMin.x, visualMin.y, visualMin.z + visualExtents.z),
//                SIMD3<Float>(visualMin.x + visualExtents.x, visualMin.y, visualMin.z + visualExtents.z),
//                SIMD3<Float>(visualMin.x, visualMin.y + visualExtents.y, visualMin.z + visualExtents.z),
//                SIMD3<Float>(visualMin.x + visualExtents.x, visualMin.y + visualExtents.y, visualMin.z + visualExtents.z)
//            ]
//            
//            // Rotate all corners
//            let rotatedCorners = corners.map { rotation.act($0) }
//            
//            // Find new bounds from rotated corners
//            var newMin = rotatedCorners[0]
//            var newMax = rotatedCorners[0]
//            
//            for corner in rotatedCorners {
//                newMin.x = min(newMin.x, corner.x)
//                newMin.y = min(newMin.y, corner.y)
//                newMin.z = min(newMin.z, corner.z)
//                newMax.x = max(newMax.x, corner.x)
//                newMax.y = max(newMax.y, corner.y)
//                newMax.z = max(newMax.z, corner.z)
//            }
//            
//            visualMin = newMin
//            visualExtents = newMax - newMin
//        }
//        
//        print("\nTerrain bounds - X: [\(visualMin.x), \(visualMin.x + visualExtents.x)]")
//        print("Terrain bounds - Z: [\(visualMin.z), \(visualMin.z + visualExtents.z)]")
//        
//        // Scale factors to stretch splat image to terrain dimensions
//        let scaleX = visualExtents.x / Float(imageSize.width)
//        let scaleZ = visualExtents.z / Float(imageSize.height)
//        
//        print("Scale factors - X: \(scaleX), Z: \(scaleZ)")
//        
//        return pixelVerts.map { pixelCoord in
//            // Map pixel coordinates to terrain's local space
//            SIMD2<Float>(
//                visualMin.x + pixelCoord.x * scaleX,
//                visualMin.z + pixelCoord.y * scaleZ
//            )
//        }
//    }
//    
//    // MARK: - Normal Generation
//    
//    /// Rebuilds per-triangle normals from vertices and triangles
//    private func rebuildNormals() {
//        normals.removeAll(keepingCapacity: true)
//        for i in stride(from: 0, to: triangles.count, by: 3) {
//            let v0 = triangles[i]
//            let v1 = triangles[i + 1]
//            let v2 = triangles[i + 2]
//            
//            // Validate indices
//            guard v0 >= 0 && v0 < vertices.count &&
//                  v1 >= 0 && v1 < vertices.count &&
//                  v2 >= 0 && v2 < vertices.count else {
//                normals.append([0, 1, 0]) // Default up normal
//                continue
//            }
//            
//            let e0 = vertices[Int(v1)] - vertices[Int(v0)]
//            let e1 = vertices[Int(v2)] - vertices[Int(v0)]
//            let n = cross(e0, e1)
//            let len = simd_length(n)
//            normals.append(len > 0 ? n / len : n)
//        }
//    }
//    
//    // MARK: - OBJ File Parsing
//    
//    /// Parses OBJ format text into vertices and triangles
//    private func parseOBJ(_ rawOBJ: String) throws {
//        let lines = rawOBJ
//            .replacingOccurrences(of: "\r", with: "")
//            .split(separator: "\n")
//        
//        for line in lines {
//            switch line.first {
//            case "v": // vertex
//                if line.starts(with: "v ") {
//                    let p = line.split(separator: " ")
//                    guard p.count >= 4 else { throw LoadError.invalidFormat }
//                    vertices.append([Float(p[1]) ?? 0,
//                                     Float(p[2]) ?? 0,
//                                     Float(p[3]) ?? 0])
//                }
//                
//            case "f": // face (as polygon or triangle fan)
//                let vCount = Int32(vertices.count)
//                let parts = line.split(whereSeparator: { $0.isWhitespace }).dropFirst()
//                let faceIdxs = parts.map { part -> Int32 in
//                    if let slash = part.firstIndex(of: "/") {
//                        return Int32(part[..<slash]) ?? 0
//                    } else {
//                        return Int32(part) ?? 0
//                    }
//                }.map { $0 < 0 ? vCount : $0 - 1 } // Handle negative indices
//                
//                guard faceIdxs.count > 2 else { break }
//                let a = faceIdxs[0]
//                for i in 2..<faceIdxs.count {
//                    let b = faceIdxs[i - 1]
//                    let c = faceIdxs[i]
//                    guard (0..<vCount).contains(a),
//                          (0..<vCount).contains(b),
//                          (0..<vCount).contains(c) else { continue }
//                    triangles.append(contentsOf: [a, b, c])
//                }
//                
//            case "#", "m", "u", "o", "g": break // Ignore comments, mtllib, etc.
//            default: break
//            }
//        }
//        rebuildNormals()
//    }
//    
//    // MARK: - OBJ File Writing
//    
//    /// Writes mesh data to an OBJ file
//    func writeOBJ(to url: URL) throws {
//        var obj = ""
//        for v in vertices {
//            obj += String(format: "v %.6f %.6f %.6f\n", v.x, v.y, v.z)
//        }
//        for i in stride(from: 0, to: triangles.count, by: 3) {
//            obj += "f \(triangles[i] + 1) \(triangles[i + 1] + 1) \(triangles[i + 2] + 1)\n"
//        }
//        try obj.write(to: url, atomically: true, encoding: .utf8)
//    }
//}
//
//// MARK: - Entity Extensions
//
//extension Entity {
//    /// Performs depth-first traversal, executing closure on each entity
//    func visit(_ body: (Entity) -> Void) {
//        body(self)
//        children.forEach { $0.visit(body) }
//    }
//}
//
//// MARK: - ModelEntity Extensions
//
//extension ModelEntity {
//    /// Computes precise X-Z bounds from all vertex data in local space
//    func exactLocalXZBounds() -> (min: SIMD2<Float>, max: SIMD2<Float>) {
//        var minX = Float.infinity, maxX = -Float.infinity
//        var minZ = Float.infinity, maxZ = -Float.infinity
//        
//        visit { entity in
//            guard let modelComp = entity.components[ModelComponent.self] else { return }
//            
//            let bbox = modelComp.mesh.bounds
//            minX = min(minX, bbox.min.x)
//            maxX = max(maxX, bbox.max.x)
//            minZ = min(minZ, bbox.min.z)
//            maxZ = max(maxZ, bbox.max.z)
//        }
//        return (SIMD2<Float>(minX, minZ), SIMD2<Float>(maxX, maxZ))
//    }
//}
