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
    
    do {
        let config = NavMeshBuilder.Config(partitionStyle: .monotone)
        
        print("Building NavMesh with custom road areas...")
        let navMesh = try NavMeshBuilder(
            vertices: mainMeshData.vertices,
            triangles: mainMeshData.triangles,
            areaVertices: roadMeshData.vertices,
            areaTriangles: roadMeshData.triangles,
            areaCode: NavMeshAreaCode.road, // Mark as road area (code: 2)
            config: config,
            debug: true // Enable debug output to see the process
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
