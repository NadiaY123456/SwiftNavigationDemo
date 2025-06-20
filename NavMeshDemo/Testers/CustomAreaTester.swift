//
//  CustomAreaTester.swift
//  NavMeshDemo
//
//  Created by Nadia Yilmaz on 6/19/25.
//

import Foundation
import RealityKit
import SwiftNavigation

func testCustomAreaLoader() throws -> NavMesh? {
    let mainMeshFile = "planeLarge.obj"
    let roadMeshFile = "plane.obj"
    
    print("Loading main mesh: \(mainMeshFile)")
    let mainMeshData = try ObjMeshLoader(file: "/Users/nata/GitHub/Practicing/SwiftNavigationDemo/NavMeshDemo/Data/\(mainMeshFile)")
    
    print("Loading road mesh: \(roadMeshFile)")
    let roadMeshData = try ObjMeshLoader(file: "/Users/nata/GitHub/Practicing/SwiftNavigationDemo/NavMeshDemo/Data/\(roadMeshFile)")
    
    // Define multiple areas
    let areas = [
//        NavMeshBuilder.AreaDefinition(
//            vertices: grassMesh.vertices,
//            triangles: grassMesh.triangles,
//            areaCode: NavMeshAreaCode.grass
//        ),
        NavMeshBuilder.AreaDefinition(
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
        let config = NavMeshBuilder.Config(partitionStyle: .monotone)
        
        print("Building NavMesh with custom road areas...")
        // Build nav mesh with all areas
        let navMesh = try NavMeshBuilder(
            vertices: mainMeshData.vertices,
            triangles: mainMeshData.triangles,
            areas: areas,
            config: config
        )
        
        print("Creating navigator...")
        let navigator = try navMesh.makeNavMesh(
            agentHeight: 1,
            agentRadius: 0.3,
            agentMaxClimb: 20
        )
        
        print("NavMesh created successfully!")
        print("Main mesh: \(mainMeshFile)")
        print("Road areas from: \(roadMeshFile)")
        print("Navigator: \(navigator)")
        
        return navigator
        
    } catch let e {
        print("Error creating NavMesh with custom areas: \(e)")
        throw e
    }
}
