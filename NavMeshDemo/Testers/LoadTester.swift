//
//  LoadTester.swift
//  NavMeshDemo
//
//  Created by Nadia Yilmaz on 6/19/25.
//

import Foundation
import RealityKit
import SwiftNavigation

// MARK: - Test Loading from *.obj file

func testLoader() throws -> NavMesh? {
    let files = ["plane.obj", "planeLarge.obj"]

    for file in files {
        let data = try MeshLoader(file: "/Users/nata/GitHub/Practicing/SwiftNavigationDemo/NavMeshDemo/Data/\(file)")

        do {
            var config = NavMeshConfig()
            config.partitionStyle = .monotone
            config.agentHeight = 1
            config.agentRadius = 0.3
            config.agentMaxClimb = 20

            // Create the builder with the config
            let builder = try NavMeshBuilder(vertices: data.vertices, triangles: data.triangles, config: config)
            print("Navmesh builder for \(file)")
            print("Tiles built: \(builder.tilesBuilt) of \(builder.totalTiles)")

            // Create the NavMesh from the builder
            let navMesh = try builder.makeNavMesh()
            print(navMesh)
            
            return navMesh

        } catch (let e) {
            print("Error On file \(file): \(e)")
            throw e
        }
    }
    return nil
}

 func testFindPath() throws {
    let data = try MeshLoader(file: "/Users/nata/GitHub/Practicing/recastnavigation/RecastDemo/Bin/Meshes/dungeon.obj")

    // Configure the navigation mesh
    var config = NavMeshConfig()
    config.partitionStyle = .monotone
    config.agentHeight = 1
    config.agentRadius = 0.3
    config.agentMaxClimb = 20

    // Build the navigation mesh
    let builder = try NavMeshBuilder(vertices: data.vertices, triangles: data.triangles, config: config)
    print("Navmesh builder ran successfully")
    let navMesh = try builder.makeNavMesh()
    print("NavMesh created successfully")

    // Create a query
    let query = try navMesh.makeQuery()
    print("Created NavMeshQuery")

    let start = try query.findRandomPoint(randomFunction: fakeRandom).get()
    let end = try query.findRandomPoint(randomFunction: fakeRandom).get()
    print("Start: \(start), End: \(end)")

    switch query.findPathCorridor(start: start, end: end) {
    case .success(let corridor):
        print("Found a path from \(start) to \(end)")
        for poly in corridor {
            print("    PolyRef: \(poly)")
        }

        // Assuming StraightPathOptions is the enum type for options
        let options: NavMeshQuery.StraightPathOptions = [.allCrossings, .areaCrossings]

        switch query.findStraightPath(startPos: start.point3, endPos: end.point3, pathCorridor: corridor, options: options) {
        case .success(let found):
            for x in 0..<found.count {
                let pidx = x*3
                print(" \(x): \(found.rawPathPoints[pidx]), \(found.rawPathPoints[pidx+1]), \(found.rawPathPoints[pidx+2]): \(found.flags[x]) at poly: \(found.polyRefs[x])")
            }
        case .failure(let d):
            print("Failed calling findStraightPath: \(d)")
        }
    case .failure(let d):
        print("Failed calling findPathCorridor error, details: \(d)")
    }
 }

// MARK: - Test Loading from *.bin navmesh file

func testBinLoader() throws {
    // Load mesh in bin format
    let selectedMesh = "navmesh_16byte"
    guard let url = Bundle.main.url(forResource: selectedMesh, withExtension: "bin")
    else {
        print("Could not find \(selectedMesh).bin")
        return
    }
    print("Loaded bin: \(selectedMesh)")

    do {
        let navigator = try NavMesh(tiledContentsOf: url, zeroCopy: true)
        print("NavMesh loaded successfully for \(selectedMesh)")
        print(navigator)
    } catch (let e) {
        print("Error On file \(selectedMesh): \(e)")
        throw e
    }
}

func testBinFindPath() throws {
    // Load mesh in bin format
    let selectedMesh = "navmesh_16byte"
    guard let url = Bundle.main.url(forResource: selectedMesh, withExtension: "bin")
    else {
        print("Could not find \(selectedMesh).bin")
        return
    }
    print("Loaded bin: \(selectedMesh)")

    let navigator = try NavMesh(tiledContentsOf: url, zeroCopy: true)
    print("NavMesh loaded successfully for \(selectedMesh)")
    print(navigator)

    let query = try navigator.makeQuery()
    print("Created NavMeshQuery")

    let start = try query.findRandomPoint(randomFunction: fakeRandom).get()
    let end = try query.findRandomPoint(randomFunction: fakeRandom).get()

    print("Start: \(start), End: \(end)")

    switch query.findPathCorridor(start: start, end: end) {
    case .success(let corridor):
        print("Found a path from \(start) to \(end)")
        for poly in corridor {
            print("    PolyRef: \(poly)")
        }
        switch query.findStraightPath(startPos: start.point3, endPos: end.point3, pathCorridor: corridor, options: [.allCrossings, .areaCrossings]) {
        case .success(let found):
            for x in 0 ..< found.count {
                let pidx = x * 3
                print(" \(x): \(found.rawPathPoints[pidx]), \(found.rawPathPoints[pidx+1]), \(found.rawPathPoints[pidx+2]): \(found.flags[x]) at poly: \(found.polyRefs[x])")
            }
        case .failure(let d):
            print("Failed calling findStraightPath: \(d)")
        }
    case .failure(let d):
        print("Failed calling findPathCorridor error, details: \(d)")
    }
}

func debugBinFindPath(selectedMesh: String) throws {
    guard let url = Bundle.main.url(forResource: selectedMesh, withExtension: "bin") else {
        print("Could not find \(selectedMesh).bin")
        return
    }

    print("=== Starting NavMesh Test ===")
    print("File: \(selectedMesh).bin")

    // First, analyze the file
    try analyzeNavMeshFile(url)

    // Test loading with different methods
    print("\n--- Test 1: Load with zeroCopy=false ---")
    do {
        let navigator = try NavMesh(tiledContentsOf: url, zeroCopy: false)
        print("✅ Successfully loaded NavMesh (copied)")

        let query = try navigator.makeQuery()
        print("✅ Created NavMeshQuery")

        // Try to find a random point
        do {
            let point = try query.findRandomPoint(randomFunction: fakeRandom).get()
            print("✅ Found random point: \(point)")
        } catch {
            print("❌ findRandomPoint failed: \(error)")
            debugError(error)
        }

    } catch {
        print("❌ Failed to load with zeroCopy=false: \(error)")
        debugError(error)
    }

    print("\n--- Test 2: Load with zeroCopy=true ---")
    do {
        let navigator = try NavMesh(tiledContentsOf: url, zeroCopy: true)
        print("✅ Successfully loaded NavMesh (mmap)")

        let query = try navigator.makeQuery()
        print("✅ Created NavMeshQuery")

        // Try to find a random point
        do {
            let point = try query.findRandomPoint(randomFunction: fakeRandom).get()
            print("✅ Found random point: \(point)")
        } catch {
            print("❌ findRandomPoint failed: \(error)")
            debugError(error)
        }

    } catch {
        print("❌ Failed to load with zeroCopy=true: \(error)")
        debugError(error)
    }

    print("\n=== Test Complete ===")
}
