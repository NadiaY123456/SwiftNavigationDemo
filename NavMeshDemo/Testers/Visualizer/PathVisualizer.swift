//
//  PathVisualizer.swift
//  NavMeshDemo
//
//  Visualizes paths in the NavMesh
//

import RealityKit
import SwiftNavigation
import simd
import UIKit

// MARK: - Path Visualization

extension NavMeshQuery.FoundPath {
    /// Creates a visual representation of the path using cylinders and spheres
    func makePathEntity(
        lineColor: UIColor = .systemGreen,
        lineRadius: Float = 0.02,
        waypointColor: UIColor = .systemYellow,
        waypointRadius: Float = 0.05,
        startColor: UIColor = .systemBlue,
        endColor: UIColor = .systemRed,
        showWaypoints: Bool = true
    ) -> Entity {
        let pathEntity = Entity()
        pathEntity.name = "NavigationPath"
        
        guard count > 0 else { return pathEntity }
        
        // Create line segments between consecutive points
        let linesEntity = Entity()
        linesEntity.name = "PathLines"
        
        for i in 0..<(count - 1) {
            let start = self[i]
            let end = self[i + 1]
            
            let segment = makePathSegment(
                from: start,
                to: end,
                radius: lineRadius,
                color: lineColor
            )
            linesEntity.addChild(segment)
        }
        pathEntity.addChild(linesEntity)
        
        // Create waypoint markers
        if showWaypoints {
            let waypointsEntity = Entity()
            waypointsEntity.name = "PathWaypoints"
            
            for i in 0..<count {
                let position = self[i]
                let flag = flags[i]
                
                // Determine waypoint appearance based on flags
                let color: UIColor
                let radius: Float
                
                if flag.contains(.start) {
                    color = startColor
                    radius = waypointRadius * 1.5
                } else if flag.contains(.end) {
                    color = endColor
                    radius = waypointRadius * 1.5
                } else if flag.contains(.offMeshConnection) {
                    color = .systemOrange
                    radius = waypointRadius * 1.2
                } else {
                    color = waypointColor
                    radius = waypointRadius
                }
                
                let waypoint = makeWaypointSphere(
                    at: position,
                    radius: radius,
                    color: color
                )
                waypointsEntity.addChild(waypoint)
            }
            pathEntity.addChild(waypointsEntity)
        }
        
        return pathEntity
    }
}

// MARK: - Helper Functions

private func makePathSegment(
    from start: SIMD3<Float>,
    to end: SIMD3<Float>,
    radius: Float,
    color: UIColor
) -> ModelEntity {
    let direction = end - start
    let length = simd_length(direction)
    guard length > 0 else { return ModelEntity() }
    
    let mesh = MeshResource.generateCylinder(height: length, radius: radius)
    let material = UnlitMaterial(color: color)
    let entity = ModelEntity(mesh: mesh, materials: [material])
    
    // Position and orient the cylinder
    let midpoint = (start + end) * 0.5
    var transform = Transform()
    transform.translation = midpoint
    
    // Rotate from Y-up to direction
    let normalizedDir = simd_normalize(direction)
    transform.rotation = simd_quatf(from: [0, 1, 0], to: normalizedDir)
    entity.transform = transform
    
    return entity
}

private func makeWaypointSphere(
    at position: SIMD3<Float>,
    radius: Float,
    color: UIColor
) -> ModelEntity {
    let mesh = MeshResource.generateSphere(radius: radius)
    let material = UnlitMaterial(color: color)
    let entity = ModelEntity(mesh: mesh, materials: [material])
    entity.position = position
    return entity
}

// MARK: - Path Generation State

/// Shared state for path generation across views
class PathGenerationState: ObservableObject {
    @Published var shouldGeneratePath = false
    @Published var currentPath: NavMeshQuery.FoundPath?
    @Published var pathStart: SIMD3<Float>?
    @Published var pathEnd: SIMD3<Float>?
}

// MARK: - Debug Path Visualization

//extension NavMeshQuery.FoundPath {
//    /// Creates a debug visualization showing polygon traversal
//    func makeDebugPathEntity(
//        polygonHeight: Float = 0.01,
//        polygonColor: UIColor = .systemPurple.withAlphaComponent(0.3)
//    ) -> Entity {
//        let debugEntity = Entity()
//        debugEntity.name = "PathDebug"
//        
//        // Create flat rectangles for each polygon in the path
//        var processedRefs = Set<dtPolyRef>()
//        
//        for i in 0..<count {
//            let polyRef = polyRefs[i]
//            guard polyRef != 0 && !processedRefs.contains(polyRef) else { continue }
//            processedRefs.insert(polyRef)
//            
//            // For now, just place a small marker at each waypoint's polygon
//            // In a full implementation, you'd query the NavMesh for polygon geometry
//            let marker = MeshResource.generateBox(
//                size: [0.1, polygonHeight, 0.1],
//                cornerRadius: 0.01
//            )
//            let material = UnlitMaterial(color: polygonColor)
//            let entity = ModelEntity(mesh: marker, materials: [material])
//            entity.position = self[i] + [0, -polygonHeight/2, 0]
//            
//            debugEntity.addChild(entity)
//        }
//        
//        return debugEntity
//    }
//}

// MARK: - Convenience quaternion helper (if not already in project)

private extension simd_quatf {
    /// Quaternion that rotates `from` vector to `to` vector
    init(from fromVec: SIMD3<Float>, to toVec: SIMD3<Float>) {
        let from = simd_normalize(fromVec)
        let to = simd_normalize(toVec)
        let dot = simd_dot(from, to)
        
        if dot > 0.9999 {
            // Vectors are parallel
            self = simd_quatf()
        } else if dot < -0.9999 {
            // Vectors are opposite, rotate 180° around any perpendicular axis
            let orthogonal = abs(from.x) < 0.1 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
            let axis = simd_normalize(simd_cross(from, orthogonal))
            self = simd_quatf(angle: .pi, axis: axis)
        } else {
            // General case
            let axis = simd_normalize(simd_cross(from, to))
            let angle = acos(dot)
            self = simd_quatf(angle: angle, axis: axis)
        }
    }
}
