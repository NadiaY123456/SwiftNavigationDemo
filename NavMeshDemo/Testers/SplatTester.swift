//
//  SplatTester.swift
//  NavMeshDemo
//
//  Created by Nadia Yilmaz on 6/20/25.
//

import UIKit

// MARK: - Usage Example

/// Generates a mesh from an image using a specific color channel
/// - Parameters:
///   - imageName: Name of the image file (e.g., "splat.png")
///   - channel: Which channel to extract (.red, .green, .blue, .alpha, or .grayscale)
///   - maxEdgeLength: Maximum edge length in image-space points (default: 20.0)
///   - simplificationTolerance: Simplification tolerance as fraction of image size (default: 0.01)
///   - threshold: Binary threshold 0-1, nil for auto (default: 0.5)
///   - invertMask: Whether to invert the binary mask (default: false)
/// - Returns: Tuple of (vertices, indices) or nil if generation fails
@MainActor
public func generateMeshFromImage(
    named imageName: String,
    channel: SplatMeshGenerator.Channel = .red,
    maxEdgeLength: CGFloat = 1.0,
    simplificationTolerance: CGFloat = 0.01,
    threshold: Float? = 0.1,
    invertMask: Bool = false
) async -> (vertices: [SIMD2<Float>], indices: [UInt32])? {
    
    // Load the image
    guard let image = UIImage(named: imageName) else {
        print("Failed to load image: \(imageName)")
        return nil
    }
    
    // Create mesh generator with specified parameters
    let meshGen = SplatMeshGenerator(
        maxEdgeLength: 50,
        simplificationTolerance: 0.0001,
        threshold: 0.25,          // tweak until the mask looks right
        channel: .green,
        invertMask: true          // <- key line
    )

    
    // Generate mesh
    do {
        let (vertices, indices) = try await meshGen.mesh(from: image)
        
        print("Successfully generated mesh from \(imageName) [\(channel)]:")
        print("  - Vertices: \(vertices.count)")
        print("  - Triangles: \(indices.count / 3)")
        print("  - Image size: \(image.size.width) x \(image.size.height)")
        
        return (vertices, indices)
        
    } catch {
        print("Mesh generation failed for \(imageName): \(error)")
        return nil
    }
}
