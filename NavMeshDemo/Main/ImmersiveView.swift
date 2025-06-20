//
//  ImmersiveView.swift
//  NavMeshDemo
//
//  Created by Miguel de Icaza on 9/15/23.
//

import SwiftUI
import RealityKit
import RealityKitContent

let spaceOrigin = Entity()

struct ImmersiveView: View {
    var body: some View {
        RealityView { content in
            // Create an empty entity that will act as the origin for the scene
            
//            // Add the initial RealityKit content as a child of spaceOrigin
//            if let scene = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
//                spaceOrigin.addChild(scene)
//            }
            
            // Add spaceOrigin (with its children) to the RealityView content
            content.add(spaceOrigin)
        }
    }
}

