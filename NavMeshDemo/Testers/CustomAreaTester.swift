//
//  CustomAreaTester.swift
//  NavMeshDemo
//
//  Created by Nadia Yilmaz on 6/19/25.
//

import Foundation
import RealityKit
import SwiftNavigation

func testCustomAreaLoader(printStats: Bool = false) throws -> NavMesh? {
    let mainMeshFile = "foothill.obj"
    let roadMeshFile = "splatBlue.obj"
    
    print("Loading main mesh: \(mainMeshFile)")
    let mainMeshData = try MeshLoader(file: "/Users/nata/GitHub/Practicing/SwiftNavigationDemo/NavMeshDemo/Data/\(mainMeshFile)")
    
    print("Loading road mesh: \(roadMeshFile)")
    let roadMeshData = try MeshLoader(file: "/Users/nata/GitHub/Practicing/SwiftNavigationDemo/NavMeshDemo/Data/\(roadMeshFile)")
    
    // Define multiple areas
    let areas = [
//        NavMeshBuilder.AreaDefinition(
//            vertices: grassMesh.vertices,
//            triangles: grassMesh.triangles,
//            areaCode: NavMeshAreaCode.grass
//        ),
        AreaDefinition(
            vertices: roadMeshData.vertices,
            triangles: roadMeshData.triangles,
            areaCode: NavMeshAreaCode.road
        ),
//        NavMeshBuilder.AreaDefinition(
//            vertices: waterMesh.vertices,
//            triangles: waterMesh.triangles,
//            areaCode: NavMeshAreaCode.water
//        )
    ]
    
    do {
        let config = customNavMeshConfig
        
        print("Testing NavMeshBuilder with custom areas...")
        
        // Debug the area definitions
        let testBuilder = try NavMeshBuilder(
            vertices: mainMeshData.vertices,
            triangles: mainMeshData.triangles,
            config: config,
            areas: []  // Empty for bounds calculation
        )
        testBuilder.debugAreaDefinitions(areas)
        
        print("Building NavMesh with custom road areas...")
        // Build nav mesh with all areas
        let navMesh = try NavMeshBuilder(
            vertices: mainMeshData.vertices,
            triangles: mainMeshData.triangles,
            config: config,
            areas: areas
        )
        
        print("Creating navigator...")
        let navigator = try navMesh.makeNavMesh()
        
        print("NavMesh created successfully!")
        print("Main mesh: \(mainMeshFile)")
        print("Road areas from: \(roadMeshFile)")
        print("Navigator: \(navigator)")
        
        if printStats {
            let navMeshGeometry = navigator.extractGeometry(verbose: true)
            navMeshGeometry.printStatistics()
        }
        print("Custom area loader test completed!")
        return navigator
        
    } catch let e {
        print("Error creating NavMesh with custom areas: \(e)")
        throw e
    }
}
