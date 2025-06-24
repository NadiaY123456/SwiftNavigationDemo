//
//  GeometryTester.swift
//  NavMeshDemo
//
//  Created by Nataliya Kuribko on 6/18/25.
//

import Foundation
import RealityKit
import simd
import SwiftNavigation

func testGeometry(selectedMesh: String) throws -> NavMeshGeometry? {
    #if false
    // Load mesh in bin format
    selectedMesh = "swiftNavMeshGeometryTester"
    guard let url = Bundle.main.url(forResource: selectedMesh, withExtension: "bin")
    else {
        print("❌ Could not find \(selectedMesh).bin")
        return nil
    }
    print("Loaded bin: \(selectedMesh)")

    let navMeshGeometry: NavMeshGeometry
    do {
        let navMesh = try NavMesh(tiledContentsOf: url, zeroCopy: true)
        print("NavMesh loaded successfully for \(selectedMesh)")
        print(navMesh)
        
        // Extract geometry with verbose logging
        navMeshGeometry = navMesh.extractGeometry(verbose: true)
    } catch let e {
        print("❌ Error On file \(selectedMesh): \(e)")
        throw e
    }
    #endif
    
    #if true
    // Load mesh in obj format
    let navMeshGeometry: NavMeshGeometry
    do {
        if let navMesh = try testCustomAreaLoader() {
            print("NavMesh generates successfully")
            print(navMesh)
            
            // Extract geometry with verbose logging
            navMeshGeometry = navMesh.extractGeometry(verbose: true)
        } else {
            print("❌ Failed to generate NavMesh")
            return nil
        }
    } catch let e {
        print("❌ Error On file \(selectedMesh): \(e)")
        throw e
    }
    #endif
    
    #if false
    // create mesh
    let navMeshGeometry: NavMeshGeometry
    do {
        if let navMesh = try testLoader() {
            print("NavMesh generates successfully")
            print(navMesh)
        
            // Extract geometry with verbose logging
            navMeshGeometry = navMesh.extractGeometry(verbose: true)
        } else {
            print("❌ Failed to generate NavMesh")
            return nil
        }
    } catch let e {
        print("❌ Error On file \(selectedMesh): \(e)")
        throw e
    }
    #endif
    
    let exportPath = "/Users/nata/Library/CloudStorage/OneDrive-Personal/CNC/VisionPro/World/swiftNavMeshGeometryTester.obj"
    let exportURL = URL(fileURLWithPath: exportPath)

    do {
        try OBJParser.write(polygons: navMeshGeometry.polygons, to: exportURL)
        print("✅ NavMesh exported to OBJ at \(exportPath)")
    } catch {
        print("❌ Failed to export NavMesh OBJ: \(error)")
    }
    
    print("\n📊 Geometry Statistics:")
    print("  Total polygons: \(navMeshGeometry.polygons.count)")
    
    if let firstPoly = navMeshGeometry.polygons.first {
        print("\n🔍 First polygon details:")
        print("  Ref: \(firstPoly.ref)")
        print("  Vertex count: \(firstPoly.vertices.count)")
        print("  Vertices: \(firstPoly.vertices)")
        print("  Neighbors: \(firstPoly.neighbours)")
        print("  Area: \(firstPoly.area)")
        print("  Flags: \(firstPoly.flags)")
        print("  Type: \(firstPoly.type)")
    }
    
    // Calculate bounds
    var minBounds = SIMD3<Float>(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
    var maxBounds = SIMD3<Float>(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
    
    for poly in navMeshGeometry.polygons {
        for vertex in poly.vertices {
            minBounds = min(minBounds, vertex)
            maxBounds = max(maxBounds, vertex)
        }
    }
    
    print("\n📏 Mesh bounds:")
    print("  Min: \(minBounds)")
    print("  Max: \(maxBounds)")
    print("  Size: \(maxBounds - minBounds)")
    
    // Analyze polygon connectivity
    var connectionCount = 0
    for poly in navMeshGeometry.polygons {
        connectionCount += poly.neighbours.count
    }
    let avgConnections = Float(connectionCount) / Float(navMeshGeometry.polygons.count)
    print("\n🔗 Connectivity:")
    print("  Average connections per polygon: \(avgConnections)")
    
    // Find polygons by area type
    var areaTypes: [UInt8: Int] = [:]
    for poly in navMeshGeometry.polygons {
        areaTypes[poly.area, default: 0] += 1
    }
    print("\n🏷️ Area types:")
    for (area, count) in areaTypes.sorted(by: { $0.key < $1.key }) {
        print("  Area \(area): \(count) polygons")
    }
    
    return navMeshGeometry
}
