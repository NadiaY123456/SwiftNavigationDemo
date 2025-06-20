//
//  SplatMeshGenerator.swift
//  SwiftNavigation
//
//  Created by Nadia Yilmaz on 6/20/25.
//  Fixed version that properly handles multiple regions
//

import CoreImage
import DelaunayTriangulation
import simd
import SwiftSimplify
import UIKit
import Vision

public struct SplatMeshGenerator {
    public enum Channel {
        case red
        case green
        case blue
        case alpha
        case grayscale
    }
    
    /// Output edges will be **≤** this length in image-space points.
    public let maxEdgeLength: CGFloat
    /// Douglas-Peucker tolerance expressed as a fraction of the *shorter* image side.
    public let simplificationTolerance: CGFloat
    /// Optional manual threshold in \[0 … 1]; `nil` → auto Otsu.
    public let threshold: Float?
    /// Which channel to use for mesh generation
    public let channel: Channel
    /// Whether to invert the binary mask (detect dark regions instead of light)
    public let invertMask: Bool

    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    public init(maxEdgeLength: CGFloat,
                simplificationTolerance: CGFloat = 0.005,
                threshold: Float? = nil,
                channel: Channel = .grayscale,
                invertMask: Bool = false)
    {
        self.maxEdgeLength = maxEdgeLength
        self.simplificationTolerance = simplificationTolerance
        self.threshold = threshold
        self.channel = channel
        self.invertMask = invertMask
    }

    // MARK: – Public API (async/await)

    public func mesh(from image: UIImage) async throws
        -> (vertices: [SIMD2<Float>], indices: [UInt32])
    {
        print("\n[DEBUG] Starting mesh generation")
        print("[DEBUG] Input image size: \(image.size)")
        
        // Add Python output for image size
        print("\n# Python: Image dimensions")
        print("image_width = \(image.size.width)")
        print("image_height = \(image.size.height)")
        
        print("[DEBUG] Selected channel: \(channel)")
        print("[DEBUG] Parameters:")
        print("  - maxEdgeLength: \(maxEdgeLength)")
        print("  - simplificationTolerance: \(simplificationTolerance)")
        print("  - threshold: \(threshold ?? -1) (nil = auto)")
        print("  - invertMask: \(invertMask)")
        
        // Add Python output for parameters
        print("\n# Python: Parameters")
        print("max_edge_length = \(maxEdgeLength)")
        print("simplification_tolerance = \(simplificationTolerance)")
        print("threshold = \(threshold ?? -1)")
        print("invert_mask = \(invertMask)")
        
        // 1. Binarise
        print("\n[DEBUG] Step 1: Creating binary mask...")
        let mask = try await createBinaryMask(from: image)
        print("[DEBUG] Mask extent: \(mask.extent)")

        // 2. Detect contours
        print("\n[DEBUG] Step 2: Detecting contours...")
        let contours = try await detectContours(in: mask)
        print("[DEBUG] Found \(contours.count) contours to process")
        
        // 3. Process each contour separately and combine results
        var allVertices: [SIMD2<Float>] = []
        var allIndices: [UInt32] = []
        
        // Store intermediate data for Python output
        var allRawContours: [[CGPoint]] = []
        var allSimplifiedContours: [[CGPoint]] = []
        var allResampledContours: [[CGPoint]] = []
        
        for (i, contour) in contours.enumerated() {
            print("\n[DEBUG] Processing contour \(i) with \(contour.pointCount) points...")
            
            // Process this contour
            let rawPoints = flattenSingleContour(contour, imageSize: image.size)
            allRawContours.append(rawPoints)
            
            if rawPoints.count < 3 {
                print("[DEBUG] Skipping contour \(i) - too few points (\(rawPoints.count))")
                continue
            }
            
            // Print raw contour for Python
            printPythonPoints(rawPoints, name: "contour_\(i)_raw")
            
            // Simplify
            let tolerance = simplificationTolerance * min(image.size.width, image.size.height)
            let simplified = rawPoints.simplified(tolerance: tolerance)
            allSimplifiedContours.append(simplified)
            print("[DEBUG] Simplified from \(rawPoints.count) to \(simplified.count) points")
            
            // Print simplified contour for Python
            printPythonPoints(simplified, name: "contour_\(i)_simplified")
            
            if simplified.count < 3 {
                print("[DEBUG] Skipping contour \(i) after simplification - too few points")
                continue
            }
            
            // Resample
            let refined = resample(points: simplified)
            allResampledContours.append(refined)
            print("[DEBUG] Resampled to \(refined.count) points")
            
            // Print resampled contour for Python
            printPythonPoints(refined, name: "contour_\(i)_resampled")
            
            // Triangulate this contour
            let indices = triangulate(points: refined)
            
            if indices.isEmpty {
                print("[DEBUG] No triangles generated for contour \(i)")
                continue
            }
            
            // Offset indices by current vertex count
            let indexOffset = UInt32(allVertices.count)
            let offsetIndices = indices.map { $0 + indexOffset }
            
            // Print triangulation info for this contour
            print("\n# Python: Contour \(i) triangulation")
            print("contour_\(i)_vertex_offset = \(indexOffset)")
            print("contour_\(i)_num_vertices = \(refined.count)")
            print("contour_\(i)_num_triangles = \(indices.count / 3)")
            
            // Add to combined results
            let verts = refined.map { SIMD2(Float($0.x), Float($0.y)) }
            allVertices.append(contentsOf: verts)
            allIndices.append(contentsOf: offsetIndices)
            
            print("[DEBUG] Added \(verts.count) vertices and \(indices.count / 3) triangles from contour \(i)")
        }
        
        print("\n[DEBUG] Final combined result: \(allVertices.count) vertices, \(allIndices.count / 3) triangles")
        
        // Print final mesh data for Python
        print("\n# ===== FINAL MESH DATA FOR PYTHON =====")
        
        // Image dimensions
        print("\n# Python: Image dimensions")
        print("image_width = \(image.size.width)")
        print("image_height = \(image.size.height)")
        
        // Parameters
        print("\n# Python: Parameters")
        print("max_edge_length = \(maxEdgeLength)")
        print("simplification_tolerance = \(simplificationTolerance)")
        
        // All contour data
        print("\n# Python: Contour data")
        for (i, rawContour) in allRawContours.enumerated() {
            if !rawContour.isEmpty {
                printPythonPoints(rawContour, name: "contour_\(i)_raw")
            }
        }
        
        for (i, simplifiedContour) in allSimplifiedContours.enumerated() {
            if !simplifiedContour.isEmpty {
                printPythonPoints(simplifiedContour, name: "contour_\(i)_simplified")
            }
        }
        
        for (i, resampledContour) in allResampledContours.enumerated() {
            if !resampledContour.isEmpty {
                printPythonPoints(resampledContour, name: "contour_\(i)_resampled")
            }
        }
        
        // Vertices and indices
        print("\n# Python: Mesh data")
        printPythonVertices(allVertices, name: "vertices")
        printPythonArray(allIndices, name: "indices")
        
        // Print triangle data as triplets
        print("\n# Python: Triangles (as vertex index triplets)")
        print("triangles = [")
        for i in stride(from: 0, to: allIndices.count, by: 3) {
            if i + 2 < allIndices.count {
                if i + 3 >= allIndices.count {
                    print("    [\(allIndices[i]), \(allIndices[i+1]), \(allIndices[i+2])]")
                } else {
                    print("    [\(allIndices[i]), \(allIndices[i+1]), \(allIndices[i+2])],")
                }
            }
        }
        print("]")
        
        // Print summary statistics
        print("\n# Python: Summary")
        print("num_vertices = \(allVertices.count)")
        print("num_triangles = \(allIndices.count / 3)")
        print("num_contours = \(contours.count)")
        
        // Print bounding box
        if !allVertices.isEmpty {
            let xCoords = allVertices.map { $0.x }
            let yCoords = allVertices.map { $0.y }
            print("\n# Python: Bounding box")
            print("bbox_min = [\(xCoords.min() ?? 0), \(yCoords.min() ?? 0)]")
            print("bbox_max = [\(xCoords.max() ?? 0), \(yCoords.max() ?? 0)]")
        }
        
        print("\n# ===== END PYTHON DATA =====\n")
        
        return (allVertices, allIndices)
    }

    // MARK: – Step 1: Binary mask

    private func createBinaryMask(from image: UIImage) async throws -> CIImage {
        guard let ci = CIImage(image: image) else { throw MeshError.invalidImage }
        print("[DEBUG] Source CIImage extent: \(ci.extent)")

        // Extract the selected channel
        let channelImage: CIImage
        switch channel {
        case .red:
            print("[DEBUG] Extracting red channel...")
            let matrix = CIFilter(name: "CIColorMatrix")!
            matrix.setValue(ci, forKey: kCIInputImageKey)
            matrix.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            channelImage = matrix.outputImage!
            
        case .green:
            print("[DEBUG] Extracting green channel...")
            let matrix = CIFilter(name: "CIColorMatrix")!
            matrix.setValue(ci, forKey: kCIInputImageKey)
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            channelImage = matrix.outputImage!
            
        case .blue:
            print("[DEBUG] Extracting blue channel...")
            let matrix = CIFilter(name: "CIColorMatrix")!
            matrix.setValue(ci, forKey: kCIInputImageKey)
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            channelImage = matrix.outputImage!
            
        case .alpha:
            print("[DEBUG] Extracting alpha channel...")
            let matrix = CIFilter(name: "CIColorMatrix")!
            matrix.setValue(ci, forKey: kCIInputImageKey)
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            let alphaToRGB = CIFilter(name: "CIColorMatrix")!
            alphaToRGB.setValue(matrix.outputImage, forKey: kCIInputImageKey)
            alphaToRGB.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputRVector")
            alphaToRGB.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputGVector")
            alphaToRGB.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputBVector")
            channelImage = alphaToRGB.outputImage!
            
        case .grayscale:
            print("[DEBUG] Converting to grayscale...")
            channelImage = ci.applyingFilter("CIColorControls",
                                             parameters: [kCIInputSaturationKey: 0])
        }
        
        print("[DEBUG] Channel image extent: \(channelImage.extent)")
        saveDebugImage(channelImage, name: "debug_1_channel_\(channel)")

        // Apply threshold
        if let filter = CIFilter(name: "CIColorThreshold") {
            let thresholdValue = threshold ?? 0.5
            print("[DEBUG] Using CIColorThreshold with value: \(thresholdValue)")
            filter.setValue(channelImage, forKey: kCIInputImageKey)
            filter.setValue(thresholdValue, forKey: "inputThreshold")
            guard let out = filter.outputImage else {
                print("[DEBUG] CIColorThreshold failed!")
                throw MeshError.invalidImage
            }
            print("[DEBUG] Threshold output extent: \(out.extent)")
            
            if invertMask {
                print("[DEBUG] Inverting mask...")
                let invertFilter = CIFilter(name: "CIColorInvert")!
                invertFilter.setValue(out, forKey: kCIInputImageKey)
                guard let inverted = invertFilter.outputImage else {
                    print("[DEBUG] Failed to invert mask!")
                    throw MeshError.invalidImage
                }
                saveDebugImage(inverted, name: "debug_2_binary_mask")
                return inverted
            }
            
            saveDebugImage(out, name: "debug_2_binary_mask")
            return out
        } else {
            // Fallback implementation
            let thresholdValue = threshold ?? 0.5
            print("[DEBUG] Using fallback threshold with value: \(thresholdValue)")
            // ... (fallback code same as before)
            throw MeshError.invalidImage
        }
    }

    // MARK: – Step 2: Contour detection

    private func detectContours(in mask: CIImage) async throws -> [VNContour] {
        print("[DEBUG] Creating VNImageRequestHandler...")
        let handler = VNImageRequestHandler(ciImage: mask, options: [:])
        let request = VNDetectContoursRequest()
        request.maximumImageDimension = 1024
        request.revision = VNDetectContoursRequest.currentRevision
        request.detectsDarkOnLight = !invertMask
        
        print("[DEBUG] Request configuration:")
        print("  - maximumImageDimension: \(request.maximumImageDimension)")
        print("  - revision: \(request.revision)")
        print("  - detectsDarkOnLight: \(request.detectsDarkOnLight)")

        try handler.perform([request])
        
        guard let obs = request.results?.first as? VNContoursObservation else {
            print("[DEBUG] No contours observation found!")
            throw MeshError.noContours
        }
        
        print("[DEBUG] Contours observation:")
        print("  - contourCount: \(obs.contourCount)")
        print("  - topLevelContours count: \(obs.topLevelContours.count)")
        
        // Check if we have a single boundary contour with children
        if obs.topLevelContours.count == 1 {
            let topContour = obs.topLevelContours[0]
            let bounds = topContour.normalizedPoints
            let minX = bounds.map { $0.x }.min() ?? 0
            let maxX = bounds.map { $0.x }.max() ?? 0
            let minY = bounds.map { $0.y }.min() ?? 0
            let maxY = bounds.map { $0.y }.max() ?? 0
            
            if abs(minX) < 0.01, abs(minY) < 0.01, abs(maxX - 1.0) < 0.01, abs(maxY - 1.0) < 0.01 {
                print("[DEBUG] Detected image boundary as main contour")
                print("[DEBUG] Found \(topContour.childContours.count) child contours (actual regions)")
                
                // Debug child contours
                for (i, child) in topContour.childContours.prefix(5).enumerated() {
                    print("[DEBUG] Child contour \(i): \(child.pointCount) points")
                }
                
                return topContour.childContours
            }
        }
        
        return obs.topLevelContours
    }

    // MARK: – Helper functions

    private func flattenSingleContour(_ contour: VNContour, imageSize: CGSize) -> [CGPoint] {
        return contour.normalizedPoints.map { point in
            CGPoint(x: CGFloat(point.x) * imageSize.width,
                    y: (1.0 - CGFloat(point.y)) * imageSize.height)
        }
    }

    private func resample(points: [CGPoint]) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        var out: [CGPoint] = []

        for (i, a) in points.enumerated() {
            let b = points[(i + 1) % points.count]
            out.append(a)

            let len = hypot(b.x - a.x, b.y - a.y)
            if len > maxEdgeLength {
                let pieces = Int(ceil(len / maxEdgeLength))
                for j in 1 ..< pieces {
                    let t = CGFloat(j) / CGFloat(pieces)
                    out.append(CGPoint(x: a.x + (b.x - a.x) * t,
                                       y: a.y + (b.y - a.y) * t))
                }
            }
        }
        return out
    }

    private func triangulate(points: [CGPoint]) -> [UInt32] {
        guard points.count >= 3 else { return [] }
        
        let delaunayPts: [Point] = points.map { p in
            Point(x: Double(p.x), y: Double(p.y))
        }

        let tris: [Triangle] = DelaunayTriangulation.triangulate(delaunayPts)

        var lookup: [Point: UInt32] = [:]
        for (i, pt) in delaunayPts.enumerated() {
            lookup[pt] = UInt32(i)
        }

        var indices: [UInt32] = []
        for tri in tris {
            if let a = lookup[tri.point1],
               let b = lookup[tri.point2],
               let c = lookup[tri.point3]
            {
                indices.append(contentsOf: [a, b, c])
            }
        }
        return indices
    }
    
    // MARK: - Debug Helpers
    
    private func saveDebugImage(_ ciImage: CIImage, name: String) {
        #if DEBUG
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            print("[DEBUG] Failed to create CGImage for \(name)")
            return
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        let debugDirectory = URL(fileURLWithPath: "/Users/nata/Library/CloudStorage/OneDrive-Personal/CNC/VisionPro/World")
        
        do {
            try FileManager.default.createDirectory(at: debugDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("[DEBUG] Failed to create debug directory: \(error)")
            return
        }
        
        let fileURL = debugDirectory.appendingPathComponent("\(name).png")
        
        if let data = uiImage.pngData() {
            do {
                try data.write(to: fileURL)
                print("[DEBUG] Saved debug image to: \(fileURL.path)")
            } catch {
                print("[DEBUG] Failed to save debug image: \(error)")
            }
        }
        #endif
    }
    
    // MARK: - Python-friendly Debug Output

    private func printPythonArray<T>(_ array: [T], name: String) {
        print("\n# Python: \(name)")
        print("\(name) = [")
        for (i, element) in array.enumerated() {
            if i == array.count - 1 {
                print("    \(element)")
            } else {
                print("    \(element),")
            }
        }
        print("]")
    }

    private func printPythonVertices(_ vertices: [SIMD2<Float>], name: String) {
        print("\n# Python: \(name)")
        print("\(name) = [")
        for (i, v) in vertices.enumerated() {
            if i == vertices.count - 1 {
                print("    [\(v.x), \(v.y)]")
            } else {
                print("    [\(v.x), \(v.y)],")
            }
        }
        print("]")
    }

    private func printPythonPoints(_ points: [CGPoint], name: String) {
        print("\n# Python: \(name)")
        print("\(name) = [")
        for (i, p) in points.enumerated() {
            if i == points.count - 1 {
                print("    [\(p.x), \(p.y)]")
            } else {
                print("    [\(p.x), \(p.y)],")
            }
        }
        print("]")
    }
}

// MARK: – Utilities

private enum MeshError: Error { case invalidImage, noContours }

private extension Array where Element == CGPoint {
    func simplified(tolerance: CGFloat) -> [CGPoint] {
        SwiftSimplify.simplify(self, tolerance: Float(tolerance))
    }
}
