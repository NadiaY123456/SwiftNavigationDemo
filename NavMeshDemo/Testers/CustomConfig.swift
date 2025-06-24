//  CustomConfig.swift
//  NavMeshDemo

import SwiftNavigation

// Example usage:
public let customNavMeshConfig = makeNavMeshConfig(
    agentRadius: 0.4,
    cellSize: 0.2, // nil for autocalculate at agentRadius/3. set to agentRadius/2 if fails
    tileSizeUnits: 25, // nil for autocalculate at 256 * cellSize
    minRegionArea: 8,   // Smaller to preserve small road sections
    mergeRegionArea: 20 // Smaller to avoid merging road with ground
)

// MARK: - Factory for unit-based configuration

/// Builds a `NavMeshConfig` from world-unit inputs, leaving `NavMeshConfig` untouched.
/// - Parameters:
///   - agentRadius: The agent's radius in world units.
///   - cellSize: Optional horizontal cell size; defaults to agentRadius/3. Smaller cell size yields more detail at exponential build-cost; outdoors, r/2 often suffices, while indoor scenes sometimes use r/3.
///   - tileSizeUnits: Optional tile size in world units along X/Z.
///     If not provided, defaults to 256 cells per side. Production navmeshes typically use tiles of 32–128 cells per side, often scaling up to 256–512 in less-dynamic worlds.
///   - walkableRadiusUnits: Optional walkable radius in world units; defaults to agentRadius.
///   - walkableHeightUnits: Optional min floor-ceiling height in world units.
///   - walkableClimbUnits: Optional max climb height in world units.
///   - maxEdgeLenUnits: Optional max contour edge length in world units.
///   - minRegionArea: Optional minimum region span count. Smaller values preserve small regions (e.g., narrow roads). Defaults to 8.
///   - mergeRegionArea: Optional span threshold below which regions are merged. Smaller values avoid merging narrow features with ground. Defaults to 20.
public func makeNavMeshConfig(
    agentRadius: Float,
    cellSize: Float? = nil,
    tileSizeUnits: Float? = nil,
    walkableRadiusUnits: Float? = nil,
    walkableHeightUnits: Float? = nil,
    walkableClimbUnits: Float? = nil,
    maxEdgeLenUnits: Float? = nil,
    minRegionArea: Int32? = nil,
    mergeRegionArea: Int32? = nil
) -> NavMeshConfig {
    var config = NavMeshConfig()
    // Agent
    config.agentRadius = agentRadius
    // Compute cell size
    let cs = cellSize ?? agentRadius / 3
    config.cellSize = cs
    // Tile size: world units -> voxels (defaults to 256 cells per side)
    if let tileUnits = tileSizeUnits {
        config.tileSize = Int32(tileUnits / cs)
    } else {
        config.tileSize = 256
    }
    // Walkable radius
    let wrUnits = walkableRadiusUnits ?? agentRadius
    config.walkableRadius = Int32(wrUnits / cs)
    // Walkable height: use cellHeight for vertical voxel size
    if let whUnits = walkableHeightUnits {
        config.walkableHeight = Int32(whUnits / config.cellHeight)
    }
    // Walkable climb
    if let wcUnits = walkableClimbUnits {
        config.walkableClimb = Int32(wcUnits / config.cellHeight)
    }
    // Max edge length
    if let melUnits = maxEdgeLenUnits {
        config.maxEdgeLen = Int32(melUnits / cs)
    }
    // Region settings (span counts)
    // For custom areas, consider these settings:
    let mra = minRegionArea ?? 8  // Smaller to preserve small road sections
    config.minRegionArea = mra
    let mgra = mergeRegionArea ?? 20  // Smaller to avoid merging road with ground
    config.mergeRegionArea = mgra

    return config
}
