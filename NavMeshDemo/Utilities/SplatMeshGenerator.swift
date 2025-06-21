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
    /// Radius (pixels) for the dilate → erode “closing” operation; 0 = skip.
    public let morphologyRadius: Int

    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    public init(maxEdgeLength: CGFloat,
                simplificationTolerance: CGFloat = 0.005,
                threshold: Float? = nil, // nil  → auto Otsu
                channel: Channel = .grayscale,
                invertMask: Bool = false,
                morphologyRadius: Int = 2) // new default
    {
        self.maxEdgeLength = maxEdgeLength
        self.simplificationTolerance = simplificationTolerance
        self.threshold = threshold
        self.channel = channel
        self.invertMask = invertMask
        self.morphologyRadius = morphologyRadius
    }

    // MARK: – Public API (async/await)

    public func mesh(from image: UIImage) async throws -> MeshResult2D {
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
            
            #if false
            // Print raw contour for Python
            printPythonPoints(rawPoints, name: "contour_\(i)_raw")
            #endif

            // Simplify
            let tolerance = simplificationTolerance * min(image.size.width, image.size.height)
            let simplified = rawPoints.simplified(tolerance: tolerance)
            allSimplifiedContours.append(simplified)
            print("[DEBUG] Simplified from \(rawPoints.count) to \(simplified.count) points")

            #if false
            // Print simplified contour for Python
            printPythonPoints(simplified, name: "contour_\(i)_simplified")
            

            if simplified.count < 3 {
                print("[DEBUG] Skipping contour \(i) after simplification - too few points")
                continue
            }
            #endif

            // Resample
            let refined = resample(points: simplified)
            allResampledContours.append(refined)
            print("[DEBUG] Resampled to \(refined.count) points")

            #if false
            // Print resampled contour for Python
            printPythonPoints(refined, name: "contour_\(i)_resampled")
            #endif
            
            // Triangulate this contour
            let indices = triangulate(points: refined)

            if indices.isEmpty {
                print("[DEBUG] No triangles generated for contour \(i)")
                continue
            }

            // Offset indices by current vertex count
            let indexOffset = UInt32(allVertices.count)
            let offsetIndices = indices.map { $0 + indexOffset }

            #if false
            // Print triangulation info for this contour
            print("\n# Python: Contour \(i) triangulation")
            print("contour_\(i)_vertex_offset = \(indexOffset)")
            print("contour_\(i)_num_vertices = \(refined.count)")
            print("contour_\(i)_num_triangles = \(indices.count / 3)")
            #endif

            // Add to combined results
            let verts = refined.map { SIMD2(Float($0.x), Float($0.y)) }
            allVertices.append(contentsOf: verts)
            allIndices.append(contentsOf: offsetIndices)

            print("[DEBUG] Added \(verts.count) vertices and \(indices.count / 3) triangles from contour \(i)")
        }

        print("\n[DEBUG] Final combined result: \(allVertices.count) vertices, \(allIndices.count / 3) triangles")

        #if false
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

        #if false
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
                    print("    [\(allIndices[i]), \(allIndices[i + 1]), \(allIndices[i + 2])]")
                } else {
                    print("    [\(allIndices[i]), \(allIndices[i + 1]), \(allIndices[i + 2])],")
                }
            }
        }
        print("]")
        #endif

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
        #endif

        return MeshResult2D(vertices: allVertices,
                            indices: allIndices,
                            imageSize: image.size)
    }

    // MARK: – Step 1: Binary mask with auto-threshold + morphology

    private func createBinaryMask(from image: UIImage) async throws -> CIImage {
        guard let ci = CIImage(image: image) else { throw MeshError.invalidImage }
        print("[DEBUG] Source CIImage extent: \(ci.extent)")

        // --- 1. Isolate the requested channel --------------------------------------------------
        let channelImage: CIImage
        switch channel {
        case .red:
            // copy R into all RGB outputs
            channelImage = ci.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .green:
            // copy G into all RGB outputs
            channelImage = ci.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .blue:
            // copy B into all RGB outputs
            channelImage = ci.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .alpha:
            // copy α into RGB
            channelImage = ci.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .grayscale:
            // BT.709 luma → all RGB
            channelImage = ci.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.2126, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.7152, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.0722, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        }
        saveDebugImage(channelImage, name: "debug_1_channel_\(channel)")

        // --- 2. Threshold ----------------------------------------------------------------------
        let cutOff: Float = {
            if let manual = threshold { return manual }
            return try! computeOtsuThreshold(for: channelImage) // safe; fallback inside
        }()
        print("[DEBUG] Using threshold: \(cutOff) (\(threshold == nil ? "auto-Otsu" : "manual"))")

        let thresh = CIFilter(name: "CIColorThreshold")!
        thresh.setValue(channelImage, forKey: kCIInputImageKey)
        thresh.setValue(cutOff, forKey: "inputThreshold")
        guard var mask = thresh.outputImage else { throw MeshError.invalidImage }

        // CIColorThreshold → white for LOW intensities.
        // If the caller wants bright regions, flip once; otherwise leave as-is.
        if !invertMask {
            mask = CIFilter(name: "CIColorInvert",
                            parameters: [kCIInputImageKey: mask])!.outputImage!
        }

        // --- 3. Morphology ---------------------------------------------------------------------
        if morphologyRadius > 0 {
            let dilate = CIFilter(name: "CIMorphologyRectangleMaximum",
                                  parameters: [kCIInputImageKey: mask,
                                               "inputWidth": morphologyRadius,
                                               "inputHeight": morphologyRadius])!.outputImage!
            mask = CIFilter(name: "CIMorphologyRectangleMinimum",
                            parameters: [kCIInputImageKey: dilate,
                                         "inputWidth": morphologyRadius,
                                         "inputHeight": morphologyRadius])!.outputImage!
        }

        saveDebugImage(mask, name: "debug_2_binary_mask")
        return mask
    }

    // MARK: – Step 2: Contour detection

    private func detectContours(in mask: CIImage) async throws -> [VNContour] {
        print("[DEBUG] Creating VNImageRequestHandler...")
        let handler = VNImageRequestHandler(ciImage: mask, options: [:])
        let request = VNDetectContoursRequest()
        request.maximumImageDimension = 1024
        request.revision = VNDetectContoursRequest.currentRevision

        // The mask always contains *bright* shapes on a dark background after the change above.
        request.detectsDarkOnLight = false

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

    // MARK: – Geometry helpers

    /// Classic even/odd-rule test (ray-casting along +x).
    private func isPointInsidePolygon(_ p: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0 ..< polygon.count {
            let pi = polygon[i], pj = polygon[j]
            let intersect = (pi.y > p.y) != (pj.y > p.y) &&
                (p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x)
            if intersect { inside.toggle() }
            j = i
        }
        return inside
    }

    /// Returns only those triangles whose centroid lies **inside** the contour.
    private func triangulate(points: [CGPoint]) -> [UInt32] {
        guard points.count >= 3 else { return [] }

        // 1. Delaunay on the full point set
        let delaunayPts = points.map { Point(x: Double($0.x), y: Double($0.y)) }
        let tris = DelaunayTriangulation.triangulate(delaunayPts)

        // 2. Lookup table: Point  ➜  vertex-index
        var indexFor: [Point: UInt32] = [:]
        for (i, pt) in delaunayPts.enumerated() {
            indexFor[pt] = UInt32(i)
        }

        // 3. Keep only triangles whose centroid sits inside the original polygon
        var kept: [UInt32] = []
        for tri in tris {
            guard
                let ia = indexFor[tri.point1],
                let ib = indexFor[tri.point2],
                let ic = indexFor[tri.point3]
            else { continue }

            let centroid = CGPoint(
                x: (points[Int(ia)].x + points[Int(ib)].x + points[Int(ic)].x) / 3,
                y: (points[Int(ia)].y + points[Int(ib)].y + points[Int(ic)].y) / 3)

            if isPointInsidePolygon(centroid, polygon: points) {
                kept.append(contentsOf: [ia, ib, ic])
            }
        }
        return kept
    }

    // MARK: - Debug Helpers

    private func saveDebugImage(_ ciImage: CIImage, name: String) {
        #if false
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

    // MARK: – Histogram-based auto-threshold (Otsu)

    /// Returns an intensity threshold in the range 0…1 that maximises inter-class variance
    /// on the **single-channel** image passed in (e.g. the green channel you isolated).
    ///
    /// The code uses `CIAreaHistogram` (256 bins, un-scaled) → reads the red channel of
    /// the 256-pixel-wide result image into RAM → classic one-pass Otsu.
    private func computeOtsuThreshold(for singleChannel: CIImage) throws -> Float {
        let binCount = 256
        let histogramImage = singleChannel.applyingFilter(
            "CIAreaHistogram",
            parameters: [
                kCIInputExtentKey: CIVector(cgRect: singleChannel.extent),
                "inputCount": binCount,
                "inputScale": 1 // raw counts, no normalisation
            ])

        var rawBins = [UInt32](repeating: 0, count: binCount)
        ciContext.render(
            histogramImage,
            toBitmap: &rawBins,
            rowBytes: MemoryLayout<UInt32>.size * binCount,
            bounds: CGRect(x: 0, y: 0, width: binCount, height: 1),
            format: .RGBA8,
            colorSpace: nil)

        // Pull the red channel (8-bit count) into a Float array
        let counts: [Float] = rawBins.map { Float($0 & 0xFF) }

        let totalPixels = counts.reduce(0, +)
        guard totalPixels > 0 else { return 0.5 } // fallback

        // Classic Otsu
        var sumAll: Float = 0
        for (i, c) in counts.enumerated() {
            sumAll += c * Float(i)
        }

        var weightB: Float = 0
        var sumB: Float = 0
        var maxVariance: Float = -1
        var bestK = 0

        for k in 0 ..< binCount {
            weightB += counts[k]
            if weightB == 0 { continue }

            let weightF = totalPixels - weightB
            if weightF == 0 { break }

            sumB += counts[k] * Float(k)

            let meanB = sumB / weightB
            let meanF = (sumAll - sumB) / weightF
            let between = weightB * weightF * pow(meanB - meanF, 2)

            if between > maxVariance {
                maxVariance = between
                bestK = k
            }
        }

        return Float(bestK) / Float(binCount - 1) // → 0…1
    }
}

// MARK: – Utilities

private enum MeshError: Error { case invalidImage, noContours }

private extension Array where Element == CGPoint {
    func simplified(tolerance: CGFloat) -> [CGPoint] {
        SwiftSimplify.simplify(self, tolerance: Float(tolerance))
    }
}

// MARK: – Result bundle ---------------------------------------------------------

public struct MeshResult2D {
    public let vertices: [SIMD2<Float>]
    public let indices: [UInt32]
    public let imageSize: CGSize // ← new
}
