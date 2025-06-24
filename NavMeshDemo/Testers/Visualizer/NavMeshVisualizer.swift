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
    ///   - edgeRadius: The radius of edge cylinders when showEdges is true
    ///   - maxVerticesPerMesh: Maximum vertices per ModelEntity to avoid crashes (default: 10000)
    ///   - showTileBounds: If true, adds wireframe boxes showing tile boundaries
    /// - Returns: An entity ready to be inserted into your scene on the main thread.
    func makeNavMeshEntity(
        showEdges: Bool = true,
        areaColor: ((_ area: UInt8) -> Material.Color)? = nil,
        edgeRadius: Float? = 0.01,
        maxVerticesPerMesh: Int = 10000,
        showTileBounds: Bool = false
    ) -> Entity {
        // -------- Colour resolver --------
        let colorForArea: (UInt8) -> Material.Color = areaColor ?? Self.defaultColor(for:)

        // Parent that will collect a sub‑entity per tile and area.
        let parent = Entity()
        parent.name = "NavMeshSurface"

        // -------- Build a surface mesh per tile --------
        // Group polygons by their tile index
        var tileGroups: [Int: [Polygon]] = [:]
        
        for polygon in polygons {
            if tileGroups[polygon.tileIndex] == nil {
                tileGroups[polygon.tileIndex] = []
            }
            tileGroups[polygon.tileIndex]?.append(polygon)
        }
        
        print("NavMesh divided into \(tileGroups.count) tiles")
        
        // Process each tile separately
        for (tileIndex, tilePolygons) in tileGroups {
            // Find the tile info for this index
            let tileInfo = tiles.first { $0.index == tileIndex }
            let tileName = if let info = tileInfo {
                "Tile_\(info.x)_\(info.y)_idx\(tileIndex)"
            } else {
                "Tile_idx\(tileIndex)"
            }
            
            // Create a parent entity for this tile
            let tileEntity = Entity()
            tileEntity.name = tileName
            
            // Group by area within this tile
            var buckets: [UInt8: (positions: [SIMD3<Float>], indices: [UInt32])] = [:]
            
            for polygon in tilePolygons {
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
            
            // Convert each area bucket into its own ModelEntity
            for (areaID, bucket) in buckets {
                // Check if we need to split this further
                if bucket.positions.count > maxVerticesPerMesh {
                    // Split into smaller chunks
                    createChunkedModelEntities(
                        positions: bucket.positions,
                        indices: bucket.indices,
                        areaID: areaID,
                        colorForArea: colorForArea,
                        maxVertices: maxVerticesPerMesh,
                        parent: tileEntity,
                        tileName: tileName
                    )
                } else {
                    // Create a single ModelEntity for this area in this tile
                    var desc = MeshDescriptor(name: "\(tileName)_Area_\(areaID)")
                    desc.positions = .init(bucket.positions)
                    desc.primitives = .triangles(bucket.indices)
                    
                    do {
                        let mesh = try MeshResource.generate(from: [desc])
                        let unlitMaterial = UnlitMaterial(color: colorForArea(areaID))
                        let modelEntity = ModelEntity(mesh: mesh, materials: [unlitMaterial])
                        tileEntity.addChild(modelEntity)
                    } catch {
                        print("Failed to create mesh for tile \(tileName), area \(areaID): \(error)")
                    }
                }
            }
            
            parent.addChild(tileEntity)
        }

        // ─── Optional tile boundaries ────────────────────────────────────────────────
        if showTileBounds {
            let tileBoundsEntity = Entity()
            tileBoundsEntity.name = "TileBoundaries"
            
            for tileInfo in tiles {
                let boundaryLines = createTileBoundaryEntity(tileInfo: tileInfo)
                tileBoundsEntity.addChild(boundaryLines)
            }
            
            parent.addChild(tileBoundsEntity)
        }

        // ─── Optional wire-frame ─────────────────────────────────────────────────────
        guard showEdges else { return parent }

        let edgeParent = Entity()
        edgeParent.name = "NavMeshEdges"

        // Process edges by tile as well
        let edgeColor = UIColor.red
        let edgeRadius = edgeRadius ?? 0.01
        
        for (tileIndex, tilePolygons) in tileGroups {
            let tileInfo = tiles.first { $0.index == tileIndex }
            let tileName = if let info = tileInfo {
                "TileEdges_\(info.x)_\(info.y)_idx\(tileIndex)"
            } else {
                "TileEdges_idx\(tileIndex)"
            }
            
            let tileEdgeEntity = Entity()
            tileEdgeEntity.name = tileName
            
            // Count edges for this tile to potentially batch them
            var edgeCount = 0
            for polygon in tilePolygons {
                edgeCount += polygon.vertices.count
            }
            
            // If there are too many edges, we might need to batch them
            if edgeCount > 1000 {
                print("Warning: Tile \(tileName) has \(edgeCount) edges. Consider reducing edge detail.")
            }
            
            for polygon in tilePolygons {
                let verts = polygon.vertices
                guard verts.count >= 2 else { continue }

                for i in 0..<verts.count {
                    let a = verts[i]
                    let b = verts[(i + 1) % verts.count]
                    let cyl = makeEdgeCylinder(
                        from: a,
                        to: b,
                        radius: edgeRadius,
                        color: edgeColor
                    )
                    tileEdgeEntity.addChild(cyl)
                }
            }
            
            edgeParent.addChild(tileEdgeEntity)
        }

        parent.addChild(edgeParent)

        // Print statistics
        printVisualizationStatistics(tileGroups: tileGroups)

        return parent
    }
    
    /// Helper function to create chunked model entities when vertex count exceeds limit
    private func createChunkedModelEntities(
        positions: [SIMD3<Float>],
        indices: [UInt32],
        areaID: UInt8,
        colorForArea: (UInt8) -> Material.Color,
        maxVertices: Int,
        parent: Entity,
        tileName: String
    ) {
        // Group triangles into chunks
        var currentPositions: [SIMD3<Float>] = []
        var currentIndices: [UInt32] = []
        var positionMap: [Int: Int] = [:] // Original index -> new index
        var chunkIndex = 0
        
        for i in stride(from: 0, to: indices.count, by: 3) {
            let idx0 = Int(indices[i])
            let idx1 = Int(indices[i + 1])
            let idx2 = Int(indices[i + 2])
            
            // Check if adding this triangle would exceed the limit
            var neededVertices = 0
            if positionMap[idx0] == nil { neededVertices += 1 }
            if positionMap[idx1] == nil { neededVertices += 1 }
            if positionMap[idx2] == nil { neededVertices += 1 }
            
            if currentPositions.count + neededVertices > maxVertices && !currentPositions.isEmpty {
                // Create mesh for current chunk
                createSingleChunkEntity(
                    positions: currentPositions,
                    indices: currentIndices,
                    areaID: areaID,
                    colorForArea: colorForArea,
                    parent: parent,
                    tileName: tileName,
                    chunkIndex: chunkIndex
                )
                
                // Reset for next chunk
                currentPositions.removeAll(keepingCapacity: true)
                currentIndices.removeAll(keepingCapacity: true)
                positionMap.removeAll(keepingCapacity: true)
                chunkIndex += 1
            }
            
            // Add vertices if not already in current chunk
            if positionMap[idx0] == nil {
                positionMap[idx0] = currentPositions.count
                currentPositions.append(positions[idx0])
            }
            if positionMap[idx1] == nil {
                positionMap[idx1] = currentPositions.count
                currentPositions.append(positions[idx1])
            }
            if positionMap[idx2] == nil {
                positionMap[idx2] = currentPositions.count
                currentPositions.append(positions[idx2])
            }
            
            // Add remapped indices
            currentIndices.append(UInt32(positionMap[idx0]!))
            currentIndices.append(UInt32(positionMap[idx1]!))
            currentIndices.append(UInt32(positionMap[idx2]!))
        }
        
        // Create final chunk if there's remaining data
        if !currentPositions.isEmpty {
            createSingleChunkEntity(
                positions: currentPositions,
                indices: currentIndices,
                areaID: areaID,
                colorForArea: colorForArea,
                parent: parent,
                tileName: tileName,
                chunkIndex: chunkIndex
            )
        }
    }
    
    /// Creates a single model entity for a chunk
    private func createSingleChunkEntity(
        positions: [SIMD3<Float>],
        indices: [UInt32],
        areaID: UInt8,
        colorForArea: (UInt8) -> Material.Color,
        parent: Entity,
        tileName: String,
        chunkIndex: Int
    ) {
        var desc = MeshDescriptor(name: "\(tileName)_Area_\(areaID)_Chunk_\(chunkIndex)")
        desc.positions = .init(positions)
        desc.primitives = .triangles(indices)
        
        do {
            let mesh = try MeshResource.generate(from: [desc])
            let unlitMaterial = UnlitMaterial(color: colorForArea(areaID))
            let modelEntity = ModelEntity(mesh: mesh, materials: [unlitMaterial])
            parent.addChild(modelEntity)
        } catch {
            print("Failed to create chunk \(chunkIndex) for tile \(tileName), area \(areaID): \(error)")
        }
    }
    
    /// Creates wireframe entity showing tile boundaries
    private func createTileBoundaryEntity(tileInfo: TileInfo) -> Entity {
        let boundsEntity = Entity()
        boundsEntity.name = "TileBounds_\(tileInfo.x)_\(tileInfo.y)"
        
        let min = tileInfo.bounds.min
        let max = tileInfo.bounds.max
        let boundaryColor = UIColor.yellow.withAlphaComponent(0.5)
        let boundaryRadius: Float = 0.005
        
        // Bottom square
        boundsEntity.addChild(makeEdgeCylinder(
            from: SIMD3(min.x, min.y, min.z),
            to: SIMD3(max.x, min.y, min.z),
            radius: boundaryRadius,
            color: boundaryColor
        ))
        boundsEntity.addChild(makeEdgeCylinder(
            from: SIMD3(max.x, min.y, min.z),
            to: SIMD3(max.x, min.y, max.z),
            radius: boundaryRadius,
            color: boundaryColor
        ))
        boundsEntity.addChild(makeEdgeCylinder(
            from: SIMD3(max.x, min.y, max.z),
            to: SIMD3(min.x, min.y, max.z),
            radius: boundaryRadius,
            color: boundaryColor
        ))
        boundsEntity.addChild(makeEdgeCylinder(
            from: SIMD3(min.x, min.y, max.z),
            to: SIMD3(min.x, min.y, min.z),
            radius: boundaryRadius,
            color: boundaryColor
        ))
        
        // Top square
        boundsEntity.addChild(makeEdgeCylinder(
            from: SIMD3(min.x, max.y, min.z),
            to: SIMD3(max.x, max.y, min.z),
            radius: boundaryRadius,
            color: boundaryColor
        ))
        boundsEntity.addChild(makeEdgeCylinder(
            from: SIMD3(max.x, max.y, min.z),
            to: SIMD3(max.x, max.y, max.z),
            radius: boundaryRadius,
            color: boundaryColor
        ))
        boundsEntity.addChild(makeEdgeCylinder(
            from: SIMD3(max.x, max.y, max.z),
            to: SIMD3(min.x, max.y, max.z),
            radius: boundaryRadius,
            color: boundaryColor
        ))
        boundsEntity.addChild(makeEdgeCylinder(
            from: SIMD3(min.x, max.y, max.z),
            to: SIMD3(min.x, max.y, min.z),
            radius: boundaryRadius,
            color: boundaryColor
        ))
        
        // Vertical lines
        boundsEntity.addChild(makeEdgeCylinder(
            from: SIMD3(min.x, min.y, min.z),
            to: SIMD3(min.x, max.y, min.z),
            radius: boundaryRadius,
            color: boundaryColor
        ))
        boundsEntity.addChild(makeEdgeCylinder(
            from: SIMD3(max.x, min.y, min.z),
            to: SIMD3(max.x, max.y, min.z),
            radius: boundaryRadius,
            color: boundaryColor
        ))
        boundsEntity.addChild(makeEdgeCylinder(
            from: SIMD3(max.x, min.y, max.z),
            to: SIMD3(max.x, max.y, max.z),
            radius: boundaryRadius,
            color: boundaryColor
        ))
        boundsEntity.addChild(makeEdgeCylinder(
            from: SIMD3(min.x, min.y, max.z),
            to: SIMD3(min.x, max.y, max.z),
            radius: boundaryRadius,
            color: boundaryColor
        ))
        
        return boundsEntity
    }
    
    /// Print statistics about the visualization
    private func printVisualizationStatistics(tileGroups: [Int: [Polygon]]) {
        print("\n📊 NavMesh Visualization Statistics:")
        print("  Total tiles: \(tileGroups.count)")
        
        var totalPolygons = 0
        var totalVertices = 0
        var polygonsPerArea: [UInt8: Int] = [:]
        
        for (tileIndex, polygons) in tileGroups {
            totalPolygons += polygons.count
            
            for polygon in polygons {
                totalVertices += polygon.vertices.count
                polygonsPerArea[polygon.area, default: 0] += 1
            }
            
//            if let tileInfo = tiles.first(where: { $0.index == tileIndex }) {
//                print("  Tile [\(tileInfo.x),\(tileInfo.y)] (idx \(tileIndex)): \(polygons.count) polygons")
//            }
        }
        
        print("\n  Total polygons: \(totalPolygons)")
        print("  Total vertices: \(totalVertices)")
        
        print("\n  Polygons per area:")
        for (area, count) in polygonsPerArea.sorted(by: { $0.key < $1.key }) {
            print("    Area \(area): \(count) polygons")
        }
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



// Extension to help visualize tile boundaries
public extension NavMeshGeometry {
    /// Generate line segments representing tile boundaries for visualization
    func tileBoundaryLines() -> [(start: SIMD3<Float>, end: SIMD3<Float>)] {
        var lines: [(start: SIMD3<Float>, end: SIMD3<Float>)] = []

        for tile in tiles {
            let min = tile.bounds.min
            let max = tile.bounds.max

            // Bottom square
            lines.append((SIMD3(min.x, min.y, min.z), SIMD3(max.x, min.y, min.z)))
            lines.append((SIMD3(max.x, min.y, min.z), SIMD3(max.x, min.y, max.z)))
            lines.append((SIMD3(max.x, min.y, max.z), SIMD3(min.x, min.y, max.z)))
            lines.append((SIMD3(min.x, min.y, max.z), SIMD3(min.x, min.y, min.z)))

            // Top square
            lines.append((SIMD3(min.x, max.y, min.z), SIMD3(max.x, max.y, min.z)))
            lines.append((SIMD3(max.x, max.y, min.z), SIMD3(max.x, max.y, max.z)))
            lines.append((SIMD3(max.x, max.y, max.z), SIMD3(min.x, max.y, max.z)))
            lines.append((SIMD3(min.x, max.y, max.z), SIMD3(min.x, max.y, min.z)))

            // Vertical lines
            lines.append((SIMD3(min.x, min.y, min.z), SIMD3(min.x, max.y, min.z)))
            lines.append((SIMD3(max.x, min.y, min.z), SIMD3(max.x, max.y, min.z)))
            lines.append((SIMD3(max.x, min.y, max.z), SIMD3(max.x, max.y, max.z)))
            lines.append((SIMD3(min.x, min.y, max.z), SIMD3(min.x, max.y, max.z)))
        }

        return lines
    }
}

// MARK: - Additional NavMeshVisualizer Extensions

public extension NavMeshGeometry {
    /// Creates a visualization of specific tiles only
    func makeNavMeshEntity(
        forTiles tileIndices: Set<Int>,
        showEdges: Bool = true,
        areaColor: ((_ area: UInt8) -> Material.Color)? = nil,
        edgeRadius: Float? = 0.01,
        maxVerticesPerMesh: Int = 10000
    ) -> Entity {
        // Filter polygons to only include those from specified tiles
        let filteredGeometry = NavMeshGeometry(
            polygons: polygons.filter { tileIndices.contains($0.tileIndex) },
            tiles: tiles.filter { tileIndices.contains($0.index) }
        )
        
        return filteredGeometry.makeNavMeshEntity(
            forTiles: tileIndices,
            showEdges: showEdges,
            areaColor: areaColor,
            edgeRadius: edgeRadius,
            maxVerticesPerMesh: maxVerticesPerMesh
        )
    }
    
    /// Creates a visualization of tiles within a certain distance from a point
    func makeNavMeshEntity(
        nearPosition position: SIMD3<Float>,
        maxDistance: Float,
        showEdges: Bool = true,
        areaColor: ((_ area: UInt8) -> Material.Color)? = nil,
        edgeRadius: Float? = 0.01,
        maxVerticesPerMesh: Int = 10000
    ) -> Entity {
        // Find tiles within distance
        var nearbyTileIndices = Set<Int>()
        
        for tile in tiles {
            let tileCenter = (tile.bounds.min + tile.bounds.max) * 0.5
            let distance = simd_length(tileCenter - position)
            
            if distance <= maxDistance {
                nearbyTileIndices.insert(tile.index)
            }
        }
        
        return makeNavMeshEntity(
            forTiles: nearbyTileIndices,
            showEdges: showEdges,
            areaColor: areaColor,
            edgeRadius: edgeRadius,
            maxVerticesPerMesh: maxVerticesPerMesh
        )
    }
    
    /// Creates separate entities for each tile, useful for LOD or culling
    func makePerTileNavMeshEntities(
        showEdges: Bool = true,
        areaColor: ((_ area: UInt8) -> Material.Color)? = nil,
        edgeRadius: Float? = 0.01,
        maxVerticesPerMesh: Int = 10000
    ) -> [Int: Entity] {
        var tileEntities: [Int: Entity] = [:]
        
        // Group polygons by tile
        let tileGroups = Dictionary(grouping: polygons) { $0.tileIndex }
        
        for (tileIndex, tilePolygons) in tileGroups {
            let tileGeometry = NavMeshGeometry( //ERROR: 'NavMeshGeometry' initializer is inaccessible due to 'internal' protection level
                polygons: tilePolygons,
                tiles: tiles.filter { $0.index == tileIndex }
            )
            
            tileEntities[tileIndex] = tileGeometry.makeNavMeshEntity(
                forTiles: [tileIndex],
                showEdges: showEdges,
                areaColor: areaColor,
                edgeRadius: edgeRadius,
                maxVerticesPerMesh: maxVerticesPerMesh
            )
        }
        
        return tileEntities
    }
}

// MARK: - Convenience colours

private extension Material.Color {
    /// Pure white (1, 1, 1, 1) without needing UIKit.
    static let white = Material.Color(red: 1, green: 1, blue: 1, alpha: 1)
}

// MARK: - Optimized Visualization for Large NavMeshes

public extension NavMeshGeometry {
    /// Creates an optimized visualization when polygon count exceeds threshold.
    /// Instead of individual polygons, creates sub-entities per area-tile combination.
    ///
    /// - Parameters:
    ///   - polygonThreshold: If total polygons exceed this, use optimized approach (default: 500)
    ///   - showEdges: Adds a thin cylindrical wire-frame if `true`.
    ///   - areaColor: Optional closure that maps a Detour *area id* → tint.
    ///   - edgeRadius: The radius of edge cylinders when showEdges is true
    ///   - maxVerticesPerMesh: Maximum vertices per ModelEntity
    ///   - showTileBounds: If true, adds wireframe boxes showing tile boundaries
    /// - Returns: An entity ready to be inserted into your scene.
    func makeOptimizedNavMeshEntity(
        polygonThreshold: Int = 500,
        showEdges: Bool = true,
        areaColor: ((_ area: UInt8) -> Material.Color)? = nil,
        edgeRadius: Float? = 0.01,
        maxVerticesPerMesh: Int = 10000,
        showTileBounds: Bool = false
    ) -> Entity {
        // Check if we should use optimized approach
        if polygons.count <= polygonThreshold {
            // Use standard approach for smaller meshes
            return makeNavMeshEntity(
                showEdges: showEdges,
                areaColor: areaColor,
                edgeRadius: edgeRadius,
                maxVerticesPerMesh: maxVerticesPerMesh,
                showTileBounds: showTileBounds
            )
        }
        
        print("Using optimized visualization for \(polygons.count) polygons (threshold: \(polygonThreshold))")
        
        // Use optimized approach
        return makeAreaTileOptimizedEntity(
            showEdges: showEdges,
            areaColor: areaColor,
            edgeRadius: edgeRadius,
            maxVerticesPerMesh: maxVerticesPerMesh,
            showTileBounds: showTileBounds
        )
    }
    
    /// Creates sub-entities per area-tile combination for better performance with large meshes.
    private func makeAreaTileOptimizedEntity(
        showEdges: Bool,
        areaColor: ((_ area: UInt8) -> Material.Color)?,
        edgeRadius: Float?,
        maxVerticesPerMesh: Int,
        showTileBounds: Bool
    ) -> Entity {
        let colorForArea: (UInt8) -> Material.Color = areaColor ?? Self.defaultColor(for:)
        
        let parent = Entity()
        parent.name = "NavMeshSurface_Optimized"
        
        // Group polygons by tile and then by area
        var tileAreaGroups: [Int: [UInt8: [Polygon]]] = [:]
        
        for polygon in polygons {
            if tileAreaGroups[polygon.tileIndex] == nil {
                tileAreaGroups[polygon.tileIndex] = [:]
            }
            if tileAreaGroups[polygon.tileIndex]![polygon.area] == nil {
                tileAreaGroups[polygon.tileIndex]![polygon.area] = []
            }
            tileAreaGroups[polygon.tileIndex]![polygon.area]!.append(polygon)
        }
        
        print("Optimized grouping: \(tileAreaGroups.count) tiles with area subdivisions")
        
        // Process each tile-area combination
        for (tileIndex, areaGroups) in tileAreaGroups {
            let tileInfo = tiles.first { $0.index == tileIndex }
            let tileName = if let info = tileInfo {
                "Tile_\(info.x)_\(info.y)_idx\(tileIndex)"
            } else {
                "Tile_idx\(tileIndex)"
            }
            
            let tileEntity = Entity()
            tileEntity.name = tileName
            
            // Create sub-entities per area within this tile
            for (areaID, areaPolygons) in areaGroups {
                var positions: [SIMD3<Float>] = []
                var indices: [UInt32] = []
                
                // Merge all polygons of this area in this tile
                for polygon in areaPolygons {
                    let base = UInt32(positions.count)
                    positions.append(contentsOf: polygon.vertices)
                    
                    // Fan-triangulate
                    for i in 1..<(polygon.vertices.count - 1) {
                        indices.append(contentsOf: [
                            base,
                            base + UInt32(i),
                            base + UInt32(i + 1)
                        ])
                    }
                }
                
                // Create mesh for this tile-area combination
                if !positions.isEmpty {
                    if positions.count > maxVerticesPerMesh {
                        // Still need to chunk if too large
                        createChunkedModelEntities(
                            positions: positions,
                            indices: indices,
                            areaID: areaID,
                            colorForArea: colorForArea,
                            maxVertices: maxVerticesPerMesh,
                            parent: tileEntity,
                            tileName: tileName
                        )
                    } else {
                        var desc = MeshDescriptor(name: "\(tileName)_Area_\(areaID)")
                        desc.positions = .init(positions)
                        desc.primitives = .triangles(indices)
                        
                        do {
                            let mesh = try MeshResource.generate(from: [desc])
                            let unlitMaterial = UnlitMaterial(color: colorForArea(areaID))
                            let modelEntity = ModelEntity(mesh: mesh, materials: [unlitMaterial])
                            tileEntity.addChild(modelEntity)
                        } catch {
                            print("Failed to create mesh for tile \(tileName), area \(areaID): \(error)")
                        }
                    }
                }
            }
            
            parent.addChild(tileEntity)
        }
        
        // Optional tile boundaries
        if showTileBounds {
            let tileBoundsEntity = Entity()
            tileBoundsEntity.name = "TileBoundaries"
            
            for tileInfo in tiles {
                let boundaryLines = createTileBoundaryEntity(tileInfo: tileInfo)
                tileBoundsEntity.addChild(boundaryLines)
            }
            
            parent.addChild(tileBoundsEntity)
        }
        
        // Optional edges (simplified for performance)
        if showEdges {
            let edgeParent = Entity()
            edgeParent.name = "NavMeshEdges_Optimized"
            
            // For optimized mode, only show edges for tiles with fewer polygons
            let maxEdgesPerTile = 50
            let edgeColor = UIColor.red.withAlphaComponent(0.5)
            let radius = edgeRadius ?? 0.01
            
            for (tileIndex, areaGroups) in tileAreaGroups {
                let totalPolysInTile = areaGroups.values.reduce(0) { $0 + $1.count }
                
                if totalPolysInTile <= maxEdgesPerTile {
                    let tileInfo = tiles.first { $0.index == tileIndex }
                    let tileName = if let info = tileInfo {
                        "TileEdges_\(info.x)_\(info.y)_idx\(tileIndex)"
                    } else {
                        "TileEdges_idx\(tileIndex)"
                    }
                    
                    let tileEdgeEntity = Entity()
                    tileEdgeEntity.name = tileName
                    
                    for (_, areaPolygons) in areaGroups {
                        for polygon in areaPolygons {
                            let verts = polygon.vertices
                            guard verts.count >= 2 else { continue }
                            
                            for i in 0..<verts.count {
                                let a = verts[i]
                                let b = verts[(i + 1) % verts.count]
                                let cyl = makeEdgeCylinder(
                                    from: a,
                                    to: b,
                                    radius: radius,
                                    color: edgeColor
                                )
                                tileEdgeEntity.addChild(cyl)
                            }
                        }
                    }
                    
                    edgeParent.addChild(tileEdgeEntity)
                }
            }
            
            parent.addChild(edgeParent)
        }
        
        // Print statistics
        var totalSubEntities = 0
        for (_, areaGroups) in tileAreaGroups {
            totalSubEntities += areaGroups.count
        }
        
        print("\n📊 Optimized NavMesh Visualization Statistics:")
        print("  Total tiles with content: \(tileAreaGroups.count)")
        print("  Total tile-area sub-entities: \(totalSubEntities)")
        print("  Average areas per tile: \(Float(totalSubEntities) / Float(tileAreaGroups.count))")
        
        return parent
    }
}
