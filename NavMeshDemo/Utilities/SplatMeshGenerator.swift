//
//  SplatMeshGenerator.swift
//  SwiftNavigation
//
//  Updated 2025-06-21
//  • compile-error fixed (no unhandled `try`)
//  • `invertMask` is now Optional ⇒ pass `nil` for “auto”
//

import CoreImage
import DelaunayTriangulation
import simd
import SwiftSimplify
import UIKit
import Vision

// MARK: – Public entry point ----------------------------------------------------

public struct SplatMeshGenerator {
    public enum Channel { case red, green, blue, alpha, grayscale }

    /// Output edges will be **≤** this length in image-space points.
    public let maxEdgeLength: CGFloat
    /// Douglas-Peucker tolerance expressed as a fraction of the *shorter* image side.
    public let simplificationTolerance: CGFloat
    /// Optional manual threshold in [0 … 1]; `nil` → Otsu.
    public let threshold: Float?
    /// Which channel to use for mesh generation.
    public let channel: Channel
    /// `nil` → auto; `false` → detect *bright* shapes; `true` → detect *dark* shapes.
    public let invertMask: Bool?
    /// Radius (pixels) for the dilate → erode “closing” operation; 0 = skip.
    public let morphologyRadius: Int
    /// Fraction of `maxEdgeLength` to use for interior grid spacing.
    public let interiorSpacingFactor: CGFloat

    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    public init(
        maxEdgeLength: CGFloat,
        simplificationTolerance: CGFloat = 0.005,
        threshold: Float? = nil, // nil → Otsu
        channel: Channel = .grayscale,
        invertMask: Bool? = nil, // nil → auto (old default)
        morphologyRadius: Int = 2,
        interiorSpacingFactor: CGFloat = 0.8

    ) {
        self.maxEdgeLength = maxEdgeLength
        self.simplificationTolerance = simplificationTolerance
        self.threshold = threshold
        self.channel = channel
        self.invertMask = invertMask
        self.morphologyRadius = morphologyRadius
        self.interiorSpacingFactor = interiorSpacingFactor
    }

    // MARK: – High-level pipeline (async/await) ---------------------------------

    public func mesh(from image: UIImage, debugURL: URL? = nil) async throws -> MeshResult2D {
        print("\n[DEBUG] Starting mesh generation – channel:", channel)
        print("[DEBUG] invertMask:", invertMask.map { "\($0)" } ?? "auto")

        // 1. Binary mask
        let mask = try await createBinaryMask(from: image, debugURL: debugURL)

        // 2. Contours
        let contours = try await detectContours(in: mask)

        // 3. Per-contour → triangulate
        var vertices: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        for (idx, contour) in contours.enumerated() {
            print("\n[DEBUG] Processing contour \(idx) with \(contour.pointCount) points...")

            let rawPoints = flattenSingleContour(contour, imageSize: image.size)
            guard rawPoints.count >= 3 else { continue }

            let tolerance = simplificationTolerance * min(image.size.width, image.size.height)
            let simplified = rawPoints.simplified(tolerance: tolerance)
            print("[DEBUG] Simplified from \(rawPoints.count) to \(simplified.count) points")

            guard simplified.count >= 3 else { continue }

            // Resample
            let refined = resample(points: simplified)
            print("[DEBUG] Resampled to \(refined.count) points")

            // Triangulate with interior points
            let (triangulatedVertices, localIndices) = triangulateWithInterior(points: refined)

            guard !localIndices.isEmpty else {
                print("[DEBUG] No triangles generated for contour \(idx)")
                continue
            }

            // Offset indices by current vertex count
            let indexOffset = UInt32(vertices.count)
            let offsetIndices = localIndices.map { $0 + indexOffset }

            // Add ALL vertices (boundary + interior) to the result
            let verts = triangulatedVertices.map { SIMD2(Float($0.x), Float($0.y)) }
            vertices.append(contentsOf: verts)
            indices.append(contentsOf: offsetIndices)

            print("[DEBUG] Added \(verts.count) vertices (\(refined.count) boundary + \(verts.count - refined.count) interior) and \(localIndices.count / 3) triangles from contour \(idx)")
        }

        print("[DEBUG] Final: \(vertices.count) vertices, \(indices.count / 3) triangles")
        return MeshResult2D(vertices: vertices, indices: indices, imageSize: image.size)
    }

    // MARK: – Step 1: Channel isolation → threshold → morphology -----------------

    private func createBinaryMask(from image: UIImage,
                                  debugURL: URL? = nil) async throws -> CIImage {
        guard let ci = CIImage(image: image) else { throw MeshError.invalidImage }

        print("[DEBUG] Input image size: \(image.size)")
        print("[DEBUG] Input CIImage extent: \(ci.extent)")

        // (a) Extract requested channel
        var channelImage: CIImage
        switch channel {
        case .red:
            channelImage = ci.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .green:
            channelImage = ci.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .blue:
            channelImage = ci.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .alpha:
            channelImage = ci.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .grayscale:
            channelImage = ci.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.2126, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.7152, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.0722, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        }

        print("[DEBUG] Channel image extent after extraction: \(channelImage.extent)")
        // Test: Ensure extent is not infinite
        if channelImage.extent.isInfinite {
            print("[DEBUG] WARNING: Channel image has infinite extent, cropping...")
            channelImage = channelImage.cropped(to: ci.extent)
        }

        // (c) Threshold
        let cutOff: Float = {
            if let manual = threshold {
                return manual
            }

            // Try Otsu, but with fallback
            if let otsu = try? computeOtsuThreshold(for: channelImage), otsu > 0.01 && otsu < 0.99 {
                return otsu
            } else {
                print("[DEBUG] Otsu threshold failed or returned extreme value, using fallback 0.5")
                return 0.5 // Reasonable fallback
            }
        }()

        print("[DEBUG] Using threshold: \(cutOff)")

        // Create threshold filter
        guard let threshFilter = CIFilter(name: "CIColorThreshold") else {
            print("[DEBUG] Failed to create CIColorThreshold filter")
            throw MeshError.invalidImage
        }

        threshFilter.setValue(channelImage, forKey: kCIInputImageKey)
        threshFilter.setValue(cutOff, forKey: "inputThreshold")

        guard var mask = threshFilter.outputImage else {
            print("[DEBUG] CIColorThreshold produced nil output")
            throw MeshError.invalidImage
        }

        print("[DEBUG] Mask extent after threshold: \(mask.extent)")

        // (d) Inversion
        let shouldInvert: Bool = {
            if let explicit = invertMask {
                // Direct mapping - no negation!
                // invertMask = true means "invert the mask"
                // invertMask = false means "don't invert the mask"
                return explicit
            }
            // Auto mode: don't invert by default
            return false
        }()

        print("[DEBUG] Should invert: \(shouldInvert)")

        if shouldInvert {
            guard let invertFilter = CIFilter(name: "CIColorInvert") else {
                print("[DEBUG] Failed to create CIColorInvert filter")
                throw MeshError.invalidImage
            }
            invertFilter.setValue(mask, forKey: kCIInputImageKey)
            guard let inverted = invertFilter.outputImage else {
                print("[DEBUG] CIColorInvert produced nil output")
                throw MeshError.invalidImage
            }
            mask = inverted
            print("[DEBUG] Mask extent after inversion: \(mask.extent)")
        }

        // (e) Morphology
        if morphologyRadius > 0 {
            print("[DEBUG] Applying morphology with radius: \(morphologyRadius)")

            // Dilate
            guard let dilateFilter = CIFilter(name: "CIMorphologyRectangleMaximum") else {
                print("[DEBUG] Failed to create dilate filter")
                throw MeshError.invalidImage
            }
            dilateFilter.setValue(mask, forKey: kCIInputImageKey)
            dilateFilter.setValue(morphologyRadius, forKey: "inputWidth")
            dilateFilter.setValue(morphologyRadius, forKey: "inputHeight")

            guard let dilated = dilateFilter.outputImage else {
                print("[DEBUG] Dilate filter produced nil output")
                throw MeshError.invalidImage
            }

            // Erode
            guard let erodeFilter = CIFilter(name: "CIMorphologyRectangleMinimum") else {
                print("[DEBUG] Failed to create erode filter")
                throw MeshError.invalidImage
            }
            erodeFilter.setValue(dilated, forKey: kCIInputImageKey)
            erodeFilter.setValue(morphologyRadius, forKey: "inputWidth")
            erodeFilter.setValue(morphologyRadius, forKey: "inputHeight")

            guard let eroded = erodeFilter.outputImage else {
                print("[DEBUG] Erode filter produced nil output")
                throw MeshError.invalidImage
            }

            mask = eroded
            print("[DEBUG] Mask extent after morphology: \(mask.extent)")
        }

        // Final extent check
        if mask.extent.isInfinite {
            print("[DEBUG] Final mask has infinite extent, cropping to original bounds")
            mask = mask.cropped(to: ci.extent)
        }

        print("[DEBUG] Final mask extent: \(mask.extent)")

        // Verify we can create a CGImage (this is what Vision will need)
        if let testCG = ciContext.createCGImage(mask, from: mask.extent) {
            print("[DEBUG] Successfully created test CGImage: \(testCG.width)x\(testCG.height)")
        } else {
            print("[DEBUG] WARNING: Cannot create CGImage from mask!")
        }

        // ----- NEW: save a debug PNG if requested ----------------------------------
            if let url = debugURL,
               let cg = ciContext.createCGImage(mask, from: mask.extent) {

                let ui = UIImage(cgImage: cg)
                if let png = ui.pngData() {
                    try? png.write(to: url, options: .atomic)
                    print("[DEBUG] Wrote threshold mask → \(url.path)")
                }
            }
            // --------------------------------------------------------------------------

        return mask
    }

    // MARK: – Step 2: Contour detection (Vision) ----------------------------------

    private func detectContours(in mask: CIImage) async throws -> [VNContour] {
        print("[DEBUG] Creating VNImageRequestHandler...")

        guard let cgImage = ciContext.createCGImage(mask, from: mask.extent) else {
            throw MeshError.invalidImage
        }

        let handler  = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request  = VNDetectContoursRequest()
        request.maximumImageDimension = 1024            // keep or tweak
        request.detectsDarkOnLight    = false           // black-on-white mask

        try handler.perform([request])
        guard let obs = request.results?.first as? VNContoursObservation else {
            throw MeshError.noContours
        }

        print("[DEBUG] Contours: total \(obs.contourCount)")

        // --------  NEW: grab *all* contours and drop the image border -------------
        let epsilon: Float = 0.001                      // edge tolerance
        let allContours = (0..<obs.contourCount).compactMap { try? obs.contour(at: $0) }
        let realContours = allContours.filter { c in
            // A Vision border contour has every vertex on an edge (x==0/1 || y==0/1)
            let onEdge = c.normalizedPoints.allSatisfy { p in
                abs(p.x) < epsilon || abs(p.x - 1) < epsilon ||
                abs(p.y) < epsilon || abs(p.y - 1) < epsilon
            }
            return !onEdge
        }

        print("[DEBUG] Returning \(realContours.count) real contours")
        return realContours
    }

    // MARK: – Geometry helpers --------------------------------------------------

    private func flattenSingleContour(_ contour: VNContour, imageSize: CGSize) -> [CGPoint] {
        contour.normalizedPoints.map { p in
            CGPoint(x: CGFloat(p.x) * imageSize.width,
                    y: (1 - CGFloat(p.y)) * imageSize.height)
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

    private func isPointInsidePolygon(_ p: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0 ..< polygon.count {
            let pi = polygon[i], pj = polygon[j]
            let intersect =
                ((pi.y > p.y) != (pj.y > p.y)) &&
                (p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x)
            if intersect { inside.toggle() }
            j = i
        }
        return inside
    }

    private func triangulateWithInterior(points: [CGPoint]) -> (vertices: [CGPoint], indices: [UInt32]) {
        guard points.count >= 3 else { return ([], []) }

        // Calculate the area to determine if we need interior points
        var area: CGFloat = 0
        for i in 0 ..< points.count {
            let j = (i + 1) % points.count
            area += points[i].x * points[j].y - points[j].x * points[i].y
        }
        area = abs(area) / 2

        // Create a combined point set with boundary + interior points
        var allPoints = points

        // If the polygon is large enough, add interior points
        let spacing = maxEdgeLength * interiorSpacingFactor
        let areaThreshold = spacing * spacing * 2

        // Only add interior points if polygon is “big enough”
        if area > areaThreshold {
            let xCoords = points.map { $0.x }
            let yCoords = points.map { $0.y }
            let minX = xCoords.min() ?? 0
            let maxX = xCoords.max() ?? 0
            let minY = yCoords.min() ?? 0
            let maxY = yCoords.max() ?? 0

            var y = minY + spacing
            while y < maxY {
                var x = minX + spacing
                while x < maxX {
                    let pt = CGPoint(x: x, y: y)
                    if isPointInsidePolygon(pt, polygon: points) {
                        allPoints.append(pt)
                    }
                    x += spacing
                }
                y += spacing
            }
            print("[DEBUG] Added \(allPoints.count - points.count) interior points")
        }

        // Now triangulate with all points (boundary + interior)
        let dlPts = allPoints.map { Point(x: Double($0.x), y: Double($0.y)) }
        let tris = DelaunayTriangulation.triangulate(dlPts)

        // Build index lookup
        var indexFor: [Point: UInt32] = [:]
        for (i, p) in dlPts.enumerated() {
            indexFor[p] = UInt32(i)
        }

        // Keep triangles whose centroid is inside
        var kept: [UInt32] = []
        for tri in tris {
            guard
                let ia = indexFor[tri.point1],
                let ib = indexFor[tri.point2],
                let ic = indexFor[tri.point3]
            else { continue }

            let centroid = CGPoint(
                x: (allPoints[Int(ia)].x + allPoints[Int(ib)].x + allPoints[Int(ic)].x) / 3,
                y: (allPoints[Int(ia)].y + allPoints[Int(ib)].y + allPoints[Int(ic)].y) / 3)

            if isPointInsidePolygon(centroid, polygon: points) {
                kept.append(contentsOf: [ia, ib, ic])
            }
        }

        // Return both the complete point set and the indices
        return (vertices: allPoints, indices: kept)
    }

    // MARK: – Otsu threshold ----------------------------------------------------

    private func computeOtsuThreshold(for singleChannel: CIImage) throws -> Float {
        let binCount = 256
        let histogramImage = singleChannel.applyingFilter(
            "CIAreaHistogram",
            parameters: [
                kCIInputExtentKey: CIVector(cgRect: singleChannel.extent),
                "inputCount": binCount,
                "inputScale": 1
            ])

        var rawBins = [UInt32](repeating: 0, count: binCount)
        ciContext.render(
            histogramImage,
            toBitmap: &rawBins,
            rowBytes: MemoryLayout<UInt32>.size * binCount,
            bounds: CGRect(x: 0, y: 0, width: binCount, height: 1),
            format: .RGBA8,
            colorSpace: nil)

        // The histogram might be in any channel, not just red
        // Try all channels and use the one with data
        var counts: [Float] = []

        // Check each channel
        for shift in [0, 8, 16, 24] {
            let channelCounts = rawBins.map { Float(($0 >> shift) & 0xFF) }
            let total = channelCounts.reduce(0, +)
            if total > 0 {
                counts = channelCounts
                print("[DEBUG] Found histogram data in channel shift \(shift), total: \(total)")
                break
            }
        }

        let totalPixels = counts.reduce(0, +)
        guard totalPixels > 0 else {
            print("[DEBUG] No histogram data found!")
            return 0.5
        }

        // Standard Otsu algorithm
        var sumAll: Float = 0
        for (i, c) in counts.enumerated() {
            sumAll += c * Float(i)
        }

        var sumB: Float = 0
        var wB: Float = 0
        var maxVar: Float = -1
        var bestK = 0

        for k in 0 ..< binCount {
            wB += counts[k]
            if wB == 0 { continue }

            let wF = totalPixels - wB
            if wF == 0 { break }

            sumB += counts[k] * Float(k)
            let mB = sumB / wB
            let mF = (sumAll - sumB) / wF
            let between = wB * wF * pow(mB - mF, 2)

            if between > maxVar {
                maxVar = between
                bestK = k
            }
        }

        return Float(bestK) / Float(binCount - 1)
    }
}

// MARK: – Supporting types ------------------------------------------------------

private enum MeshError: Error { case invalidImage, noContours }

public struct MeshResult2D {
    public let vertices: [SIMD2<Float>]
    public let indices: [UInt32]
    public let imageSize: CGSize
}

// MARK: – Simplification helper -------------------------------------------------

private extension Array where Element == CGPoint {
    func simplified(tolerance: CGFloat) -> [CGPoint] {
        SwiftSimplify.simplify(self, tolerance: Float(tolerance))
    }
}
