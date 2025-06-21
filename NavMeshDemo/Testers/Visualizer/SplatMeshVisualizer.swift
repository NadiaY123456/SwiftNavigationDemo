//
//  SplatMeshVisualizer.swift
//  NavMeshDemo
//
//  Created by Nadia Yilmaz on 6/20/25.
//

//
//  MeshToRealityKit.swift
//  Convert mesh data to RealityKit entity
//

import RealityKit
import simd
import UIKit

/// Creates a RealityKit ModelEntity from mesh vertices and indices with optional edge visualization
/// - Parameters:
///   - vertices: Array of 2D vertices in image space
///   - indices: Array of triangle indices
///   - scale: Scale factor to convert from image space to world space (default: 0.001 = 1mm per pixel)
///   - color: Color for the mesh (default: semi-transparent green)
///   - showEdges: If true, adds edge wireframe visualization (default: true)
///   - edgeRadius: Radius of edge cylinders (default: 0.005)
///   - edgeColor: Color for edge wireframe (default: white)
/// - Returns: An Entity containing the mesh and optionally edge wireframes
@MainActor
public func createMeshEntity(
    vertices: [SIMD3<Float>],
    indices: [UInt32],
    scale: Float = 1,
    color: UIColor = UIColor.green.withAlphaComponent(0.35),
    showEdges: Bool = true,
    edgeRadius: Float = 0.005,
    edgeColor: UIColor = .white
) -> Entity? {
    guard !vertices.isEmpty, !indices.isEmpty else {
        print("Error: Empty vertices or indices")
        return nil
    }
    
    // Parent entity to hold mesh and edges
    let parent = Entity()
    parent.name = "MeshVisualization"
    
    // Convert 2D vertices to 3D by adding Z=0 and applying scale
    let vertices3D = vertices
    
    // Create main mesh surface
    let meshEntity = createSurfaceMesh(vertices3D: vertices3D, indices: indices, color: color)
    if let meshEntity = meshEntity {
        meshEntity.name = "MeshSurface"
        parent.addChild(meshEntity)
    }
    
    // Optional edge wireframe
    if showEdges {
        let edgesEntity = createEdgeWireframe(
            vertices3D: vertices3D,
            indices: indices,
            radius: edgeRadius,
            color: edgeColor
        )
        edgesEntity.name = "MeshEdges"
        parent.addChild(edgesEntity)
    }
    
    return parent
}

@MainActor
private func createSurfaceMesh(
    vertices3D: [SIMD3<Float>],
    indices: [UInt32],
    color: UIColor
) -> ModelEntity? {
    // Create mesh descriptor
    var meshDescriptor = MeshDescriptor()
    
    // Set positions
    meshDescriptor.positions = MeshBuffer(vertices3D)
    
    // Set indices (primitives)
    meshDescriptor.primitives = .triangles(indices)
    
    // Generate normals (all pointing in +Z direction for a flat mesh)
    let normals = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 1), count: vertices3D.count)
    meshDescriptor.normals = MeshBuffer(normals)
    
    do {
        // Create mesh resource
        let mesh = try MeshResource.generate(from: [meshDescriptor])
        
        // Create PhysicallyBasedMaterial instead of SimpleMaterial
        var material = PhysicallyBasedMaterial()
        material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: color)
        material.roughness = 0.5
        material.metallic = 0.0
        material.faceCulling = .none // Set face culling to none for double-sided rendering
        
        // Create model entity
        let entity = ModelEntity(mesh: mesh, materials: [material])
        
        return entity
        
    } catch {
        print("Error creating mesh: \(error)")
        return nil
    }
}




/// Creates edge wireframe visualization
@MainActor
private func createEdgeWireframe(
    vertices3D: [SIMD3<Float>],
    indices: [UInt32],
    radius: Float,
    color: UIColor
) -> Entity {
    let edgeParent = Entity()
    
    // Track unique edges to avoid duplicates
    var processedEdges = Set<EdgeKey>()
    
    // Process triangles
    for i in stride(from: 0, to: indices.count, by: 3) {
        guard i + 2 < indices.count else { continue }
        
        let i0 = Int(indices[i])
        let i1 = Int(indices[i + 1])
        let i2 = Int(indices[i + 2])
        
        // Get vertices
        guard i0 < vertices3D.count, i1 < vertices3D.count, i2 < vertices3D.count else { continue }
        
        let v0 = vertices3D[i0]
        let v1 = vertices3D[i1]
        let v2 = vertices3D[i2]
        
        // Create edges for the triangle
        let edges = [
            (i0, i1, v0, v1),
            (i1, i2, v1, v2),
            (i2, i0, v2, v0)
        ]
        
        for (idx0, idx1, vert0, vert1) in edges {
            let edgeKey = EdgeKey(idx0, idx1)
            if !processedEdges.contains(edgeKey) {
                processedEdges.insert(edgeKey)
                let cylinder = makeEdgeCylinder(from: vert0, to: vert1, radius: radius, color: color)
                edgeParent.addChild(cylinder)
            }
        }
    }
    
    return edgeParent
}

/// Helper structure to track unique edges
private struct EdgeKey: Hashable {
    let min: Int
    let max: Int
    
    init(_ a: Int, _ b: Int) {
        self.min = Swift.min(a, b)
        self.max = Swift.max(a, b)
    }
}

/// Creates a cylinder to represent an edge
@MainActor
private func makeEdgeCylinder(
    from start: SIMD3<Float>,
    to end: SIMD3<Float>,
    radius: Float,
    color: UIColor
) -> ModelEntity {
    let direction = end - start
    let length = simd_length(direction)
    
    guard length > 0 else {
        // Return empty entity for zero-length edges
        return ModelEntity()
    }
    
    let axis = simd_normalize(direction)
    let midpoint = (start + end) * 0.5
    
    // RealityKit cylinders are aligned to +Y, so rotate into place
    let mesh = MeshResource.generateCylinder(height: length, radius: radius)
    let material = SimpleMaterial(color: color, isMetallic: false)
    let entity = ModelEntity(mesh: mesh, materials: [material])
    
    var transform = Transform()
    transform.translation = midpoint
    transform.rotation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: axis)
    entity.transform = transform
    
    return entity
}

/// Quaternion rotation helper
private extension simd_quatf {
    /// Quaternion that rotates `from` into `to`.
    init(from fromVec: SIMD3<Float>, to toVec: SIMD3<Float>) {
        let from = simd_normalize(fromVec)
        let to = simd_normalize(toVec)
        let dotP = simd_dot(from, to)
        
        if dotP > 0.9999 {
            self = simd_quatf()
        } else if dotP < -0.9999 {
            // 180° flip around any perpendicular axis
            let orth = abs(from.x) < 0.1 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
            self = simd_quatf(angle: .pi, axis: simd_normalize(simd_cross(from, orth)))
        } else {
            let axis = simd_normalize(simd_cross(from, to))
            let angle = acos(dotP)
            self = simd_quatf(angle: angle, axis: axis)
        }
    }
}

/// Creates a debug visualization showing vertices as small spheres
/// - Parameters:
///   - vertices: Array of 2D vertices in image space
///   - scale: Scale factor to convert from image space to world space
///   - vertexSize: Size of vertex spheres
///   - vertexColor: Color for vertex spheres
/// - Returns: An Entity containing all vertex spheres
@MainActor
public func createDebugVertexEntity(
    vertices: [SIMD2<Float>],
    scale: Float = 0.001,
    vertexSize: Float = 0.01,
    vertexColor: UIColor = .red
) -> Entity {
    let container = Entity()
    container.name = "DebugVertices"
    
    for (i, vertex2D) in vertices.enumerated() {
        let position = SIMD3<Float>(
            vertex2D.x * scale - 1.024, // Center the mesh
            vertex2D.y * scale - 1.024,
            0.0
        )
        
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: vertexSize),
            materials: [SimpleMaterial(color: vertexColor, isMetallic: false)]
        )
        sphere.position = position
        sphere.name = "vertex_\(i)"
        
        container.addChild(sphere)
    }
    
    return container
}
