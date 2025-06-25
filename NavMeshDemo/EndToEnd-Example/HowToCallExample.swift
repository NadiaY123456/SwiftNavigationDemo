//
//  HowToCallExample.swift
//  NavMeshDemo
//
//  Created by Nataliya Kuribko on 6/25/25.
//

// MARK: - Complete Example with Pathfinding

import SwiftNavigation

@MainActor
func setupNavMeshWithCosts() async {
    // Define area configurations with costs
    let areaConfig = [
        SplatAreaConfig(
            splatName: "roads_splat",
            channelConfigs: [
                // Roads are the preferred path (lowest cost)
                SplatAreaConfig.ChannelConfig(channel: .red, areaCode: 2, cost: 0.5),
                // Sidewalks are good but not as good as roads
                SplatAreaConfig.ChannelConfig(channel: .green, areaCode: 3, cost: 0.8)
            ]
        ),
        SplatAreaConfig(
            splatName: "terrain_splat",
            channelConfigs: [
                // Grass areas are traversable but less preferred
                SplatAreaConfig.ChannelConfig(channel: .red, areaCode: 4, cost: 2.0),
                // Rocky/rough terrain is even less preferred
                SplatAreaConfig.ChannelConfig(channel: .green, areaCode: 5, cost: 3.0),
                // Sand/beach areas
                SplatAreaConfig.ChannelConfig(channel: .blue, areaCode: 6, cost: 2.5)
            ]
        ),
        SplatAreaConfig(
            splatName: "hazards_splat",
            channelConfigs: [
                // Water bodies - very high cost (almost impassable)
                SplatAreaConfig.ChannelConfig(channel: .blue, areaCode: 7, cost: 10.0),
                // Dangerous areas - extremely high cost
                SplatAreaConfig.ChannelConfig(channel: .red, areaCode: 8, cost: 20.0)
            ]
        )
    ]

    // Build the NavMesh
    let (navMesh, contentRoot) = await buildFoothillNavMeshExample(
        on: spaceOrigin,
        terrainFile: "foothill",
        display: .both,
        splatFiles: ["roads_splat", "terrain_splat", "hazards_splat"],
        splatRotationDegrees: 0.0,
        areaCodeConfig: areaConfig,
        exportDirectory: "/path/to/export"
    )

    // Use the NavMesh for pathfinding with cost-aware queries
    if let navMesh = navMesh {
        // Create and configure the query filter
        let queryFilter = NavQueryFilter()
        queryFilter.configure(with: areaConfig)

        // Optional: Exclude certain areas entirely
        // queryFilter.excludeFlags = 0x80  // Exclude area 8 (dangerous areas)

        // Create the query (fail early if allocation/navInit fails)
        guard let query = try? NavMeshQuery(nav: navMesh, maxNodes: 2048) else {
            print("❌ Failed to initialize NavMeshQuery")
            return
        }

        let startPos = SIMD3<Float>(10, 0, 10)
        let endPos = SIMD3<Float>(100, 0, 100)

        do {
            // Now calls our new convenience findPath(...)
            let pathPoints = try query.findPath(
                from: startPos,
                to: endPos,
                filter: queryFilter
            )
            print("✅ Path found with \(pathPoints.count) waypoints")
        } catch {
            print("❌ Pathfinding error: \(error)")
        }
    }
}

// MARK: - Example Usage

/*
 // Example 1: No splats (generates navmesh without custom areas)
 await buildFoothillNavMeshExample(
     on: container,
     terrainFile: "foothill",
     display: .both,
     splatFiles: [],  // Empty array - no custom areas
     exportDirectory: "/path/to/export"
 )

 // Example 2: Single splat with default area codes (auto-generated starting from 2)
 await buildFoothillNavMeshExample(
     on: container,
     terrainFile: "foothill",
     display: .both,
     splatFiles: ["splat_rgba"],
     splatRotationDegrees: 90.0,
     exportDirectory: "/path/to/export"
 )

 // Example 3: Multiple splats with custom area codes and costs
 let areaConfig = [
     SplatAreaConfig(
         splatName: "roads_splat",
         channelConfigs: [
             SplatAreaConfig.ChannelConfig(channel: .red, areaCode: 2, cost: 0.5),    // Roads - preferred path
             SplatAreaConfig.ChannelConfig(channel: .green, areaCode: 3, cost: 0.8)   // Sidewalks - good alternative
         ]
     ),
     SplatAreaConfig(
         splatName: "water_splat",
         channelConfigs: [
             SplatAreaConfig.ChannelConfig(channel: .blue, areaCode: 4, cost: 100.0)   // Water bodies - effectively impassable
         ]
     )
 ]

 let (navMesh, contentRoot) = await buildFoothillNavMeshExample(
     on: container,
     terrainFile: "foothill",
     display: .both,
     splatFiles: ["roads_splat", "water_splat"],
     splatRotationDegrees: 0.0,
     areaCodeConfig: areaConfig,
     exportDirectory: "/path/to/export"
 )

 // Configure pathfinding with costs
 if let navMesh = navMesh {
     let queryFilter = NavQueryFilter()
     queryFilter.configure(with: areaConfig)

     // Optional: Completely exclude water from pathfinding
     // queryFilter.excludeFlags = 0x10  // Exclude area 4 (water)

     let query = try navMesh.makeQuery()
     // Use query with filter for pathfinding...
 }
 */
