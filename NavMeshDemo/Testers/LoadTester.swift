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

func testLoader() throws {
//    let files = ["undulating.obj", "dungeon.obj", "nav_test.obj"]
    let files = ["plane.obj", "planeLarge.obj"]

    for file in files {
        let data = try ObjMeshLoader(file: "/Users/nata/GitHub/Practicing/SwiftNavigationDemo/NavMeshDemo/Data/\(file)")

        do {
            let config = NavMeshBuilder.Config(partitionStyle: .monotone)
            let navMesh = try NavMeshBuilder(vertices: data.vertices, triangles: data.triangles, config: config)
            print("Navmesh for \(file)")
            let navigator = try navMesh.makeNavMesh(agentHeight: 1, agentRadius: 0.3, agentMaxClimb: 20)
            print(navigator)
        } catch (let e) {
            print("Error On file \(file): \(e)")
            throw e
        }
    }
}

func testFindPath() throws {
    let data = try ObjMeshLoader(file: "/Users/nata/GitHub/Practicing/recastnavigation/RecastDemo/Bin/Meshes/dungeon.obj")
    let config = NavMeshBuilder.Config(partitionStyle: .monotone)
    let navMesh = try NavMeshBuilder(vertices: data.vertices, triangles: data.triangles, config: config)
    let navigator = try navMesh.makeNavMesh(agentHeight: 1, agentRadius: 0.3, agentMaxClimb: 20)
    let query = try navigator.makeQuery()

    let start = try query.findRandomPoint(randomFunction: fakeRandom).get()
    let end = try query.findRandomPoint(randomFunction: fakeRandom).get()

    switch query.findPathCorridor(start: start, end: end) {
    case .success(let corridor):
        print("Found a path from \(start) to \(end)")
        for poly in corridor {
            print("    PolyRef: \(poly)")
        }
        switch query.findStraightPath(startPos: start.point3, endPos: end.point3, pathCorridor: corridor, options: [.allCrossings, .areaCrossings]) {
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
