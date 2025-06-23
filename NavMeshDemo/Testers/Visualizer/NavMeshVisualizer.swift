//
//  NavMeshVisualizer.swift
//  SwiftNavigation
//
//  Created by Nadia Yilmaz on 6/18/25.
//

import RealityKit
import simd
import SwiftNavigation
import UIKit

// MARK: - Recast nav‑mesh → RealityKit

public extension NavMeshGeometry {
    /// Creates an entity that visualises the whole nav‑mesh.
    ///
    /// - Parameters:
    ///   - showEdges: Adds a thin cylindrical wire‑frame if `true`.
    ///   - areaColor: Optional closure that maps a Detour *area id* → tint. When `nil`,
    ///                a built‑in wrap‑around palette is used.
    /// - Returns: An entity ready to be inserted into your scene on the main thread.
    func makeNavMeshEntity(
        showEdges: Bool = true,
        areaColor: ((_ area: UInt8) -> Material.Color)? = nil,
        edgeRadius: Float? = 0.01
    ) -> Entity {
        // -------- Colour resolver --------
        let colorForArea: (UInt8) -> Material.Color = areaColor ?? Self.defaultColor(for:)

        // Parent that will collect a sub‑entity per Detour *area id*.
        let parent = Entity()
        parent.name = "NavMeshSurface"

        // -------- Build a surface mesh per area --------
        var buckets: [UInt8: (positions: [SIMD3<Float>], indices: [UInt32])] = [:]

        for polygon in polygons {
            let areaID = polygon.area
            var data = buckets[areaID] ?? ([], [])
            let base = UInt32(data.positions.count)

            data.positions.append(contentsOf: polygon.vertices)

            // Fan‑triangulate convex n‑gon: (0, i, i+1)
            for i in 1..<(polygon.vertices.count - 1) {
                data.indices.append(contentsOf: [
                    base,
                    base + UInt32(i),
                    base + UInt32(i + 1)
                ])
            }
            buckets[areaID] = data
        }

        // Convert each area bucket into its own ModelEntity so that it
        // can have a unique material colour.
        for (areaID, bucket) in buckets {
//            if areaID == 63 { continue } //debug 👀
            var desc = MeshDescriptor(name: "Area_\(areaID)")
            desc.positions = .init(bucket.positions)
            desc.primitives = .triangles(bucket.indices)
            let mesh = try! MeshResource.generate(from: [desc])
//            var pbrMaterial = PhysicallyBasedMaterial()
//            pbrMaterial.baseColor = .init(tint: colorForArea(areaID))
//            pbrMaterial.roughness = 0.5
//            pbrMaterial.metallic  = 0.0
//            pbrMaterial.faceCulling = .none    // ← double-sided
//            pbrMaterial.blending = .transparent(opacity: .init(scale: 1))
//
//            parent.addChild(ModelEntity(mesh: mesh, materials: [pbrMaterial]))

            let unlitMaterial = UnlitMaterial(color: colorForArea(areaID))

            parent.addChild(ModelEntity(mesh: mesh, materials: [unlitMaterial]))
        }

        // ─── Optional wire-frame ─────────────────────────────────────────────────────
        guard showEdges else { return parent }

        let edgeParent = Entity()
        edgeParent.name = "NavMeshEdges"

        // make them fatter and always bright
        let edgeColor = UIColor.red
        
        let edgeRadius = edgeRadius ?? 0.01 // ↑ up from 0.001
        for polygon in polygons {
            let verts = polygon.vertices
            guard verts.count >= 2 else { continue }

            for i in 0..<verts.count {
                let a = verts[i]
                let b = verts[(i + 1) % verts.count]
                // use the overload that takes radius+color
                let cyl = makeEdgeCylinder(
                    from: a,
                    to: b,
                    radius: edgeRadius,
                    color: edgeColor
                )
                edgeParent.addChild(cyl)
            }
        }

        parent.addChild(edgeParent)

        return parent
    }

    // MARK: - Default colour map

    /// Internal so it can be used as a default but hidden from API consumers.
    static func defaultColor(for area: UInt8) -> Material.Color {
        switch area {
        case 0, 63:
            // light grey
            return .init(red: 0.80, green: 0.80, blue: 0.80, alpha: 0.35)
        case 1:
            // brown
            return .init(red: 0.60, green: 0.40, blue: 0.20, alpha: 0.35)
        case 2:
            // blue
            return .init(red: 0.25, green: 0.25, blue: 1.00, alpha: 0.35)
        case 3:
            // green
            return .init(red: 0.35, green: 1.00, blue: 0.35, alpha: 0.35)
        default:
            // A short, visually distinct palette for all other areas
            let palette: [Material.Color] = [
                .init(red: 0.15, green: 0.85, blue: 1.00, alpha: 0.35), // cyan
                .init(red: 0.95, green: 0.35, blue: 0.90, alpha: 0.35), // magenta
                .init(red: 1.00, green: 0.75, blue: 0.25, alpha: 0.35), // orange
                .init(red: 1.00, green: 0.35, blue: 0.35, alpha: 0.35), // red
                .init(red: 0.60, green: 0.60, blue: 1.00, alpha: 0.35) // violet
            ]
            return palette[Int(area) % palette.count]
        }
    }
}

// MARK: - Helper for edge cylinders

private func makeEdgeCylinder(
    from start: SIMD3<Float>,
    to end: SIMD3<Float>,
    radius: Float = 0.005,
    color: UIColor = .white
) -> ModelEntity {
    let dir = end - start
    let length = simd_length(dir)
    guard length > 0 else { return ModelEntity() }

    // build a cylinder and give it an unlit material
    let mesh = MeshResource.generateCylinder(height: length, radius: radius)
    let material = UnlitMaterial(color: color)
    let entity = ModelEntity(mesh: mesh, materials: [material])

    // rotate + translate into place
    let axis = simd_normalize(dir)
    let midpoint = (start + end) * 0.5
    var xf = Transform()
    xf.translation = midpoint
    xf.rotation = simd_quatf(from: [0, 1, 0], to: axis)
    entity.transform = xf

    return entity
}

// MARK: - Minimal quaternion helper

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

// MARK: - Convenience colours

private extension Material.Color {
    /// Pure white (1, 1, 1, 1) without needing UIKit.
    static let white = Material.Color(red: 1, green: 1, blue: 1, alpha: 1)
}
