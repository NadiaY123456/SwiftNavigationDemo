import RealityKit
import simd
import SwiftNavigation
import UIKit

// MARK: - Example Visualization

/// Choose what to visualise when building the demo.
public enum DisplayOption {
    case navMeshOnly // default – keeps existing behaviour
    case terrainOnly
    case both
}

/// Example function to build a NavMesh for the "foothill" model and visualize it under a given scene origin.

/*
 • `FoothillDisplayOption.none` — render nothing, useful if you only want export stats/OBJ.
 • `terrainFile` (String) — accepts either a USDZ/RealityKit model **name** *or* an absolute/relative
   path to an `.obj`.  The terrain source is inferred from the file‑extension.
 • `splatFiles` ([String]) — array of splat texture filenames. If empty, generates navmesh without custom areas.
 • `splatRotationDegrees` inputs so callers can swap textures or orientations easily (applies to all splats).
 • `areaCodeConfig` ([SplatAreaConfig]?) — optional configuration for area codes per splat/channel. If nil, auto-generates from 2 upwards.
 */

// MARK: Visual toggle

public enum FoothillDisplayOption {
    case navMesh
    case terrain
    case both
    case none
}

// MARK: Area Code Configuration

/// Configuration for area codes in a splat image
public struct SplatAreaConfig {
    public let splatName: String
    public let channelAreaCodes: [(channel: SplatMeshGenerator.Channel, areaCode: UInt8)]

    public init(splatName: String, channelAreaCodes: [(channel: SplatMeshGenerator.Channel, areaCode: UInt8)]) {
        self.splatName = splatName
        self.channelAreaCodes = channelAreaCodes
    }
}

// MARK: - Modified version that returns NavMesh

@MainActor
public func buildFoothillNavMeshExample(
    on spaceOrigin: Entity,
    terrainFile: String,
    display: FoothillDisplayOption = .both,
    splatFiles: [String] = ["splat_rgba"],
    splatRotationDegrees: CGFloat = 90.0,
    areaCodeConfig: [SplatAreaConfig]? = nil,
    exportDirectory: String
) async -> (navMesh: NavMesh?, contentRoot: Entity?) {
    // ────────────────────────────────────────────────
    // 1️⃣ Resolve terrain source from the file-extension
    // ────────────────────────────────────────────────
    let ext = URL(fileURLWithPath: terrainFile).pathExtension.lowercased()
    let terrainSource: NavMeshGenerator.TerrainSource
    switch ext {
    case "obj":
        terrainSource = .obj(path: terrainFile, scale: 1.0)
        print("Using OBJ terrain: \(terrainFile)")
    case "usdz", "usd":
        let name = URL(fileURLWithPath: terrainFile).deletingPathExtension().lastPathComponent
        terrainSource = .model(name: name)
        print("Using USDZ terrain: \(name)")
    default:
        terrainSource = .model(name: terrainFile)
        print("Using bundled model: \(terrainFile)")
    }

    // Determine visibility
    let showNavMesh = (display == .navMesh) || (display == .both)
    let showTerrain = (display == .terrain) || (display == .both)

    // ────────────────────────────────────────────────
    // 2️⃣ Build NavMesh & Exports (only if requested)
    // ────────────────────────────────────────────────
    var geometry: NavMeshGeometry?
    var navMesh: NavMesh?

    if showNavMesh {
        // ────────────────────────────────────────────────
        // Process splat files (if any)
        // ────────────────────────────────────────────────
        var splatDescriptors: [NavMeshGenerator.SplatDescriptor] = []

        if !splatFiles.isEmpty {
            var currentAreaCode: UInt8 = 2 // Start auto-generation from 2

            for (index, splatFile) in splatFiles.enumerated() {
                guard let originalSplat = UIImage(named: splatFile) else {
                    print("❌ Failed to load splat \(splatFile) - skipping")
                    continue
                }

                // Apply rotation to splat
                let rotatedSplat: UIImage
                switch Int(splatRotationDegrees) % 360 {
                case 0: rotatedSplat = originalSplat
                case 90: rotatedSplat = originalSplat.rotated90Clockwise()!
                case 270: rotatedSplat = originalSplat.rotated90CounterClockwise()!
                default: rotatedSplat = originalSplat.rotated(degrees: splatRotationDegrees) ?? originalSplat
                }

                // Determine channels and area codes for this splat
                var channels: [NavMeshGenerator.SplatDescriptor.ChannelInfo] = []

                if let config = areaCodeConfig?.first(where: { $0.splatName == splatFile }) {
                    // Use provided area codes
                    for (channel, areaCode) in config.channelAreaCodes {
                        channels.append(NavMeshGenerator.SplatDescriptor.ChannelInfo(
                            channel: channel,
                            areaCode: areaCode
                        ))
                    }
                } else {
                    // Auto-generate area codes for common channels
                    // Default: use green and blue channels if they exist
                    let defaultChannels: [SplatMeshGenerator.Channel] = [.green, .blue]
                    for channel in defaultChannels {
                        channels.append(NavMeshGenerator.SplatDescriptor.ChannelInfo(
                            channel: channel,
                            areaCode: currentAreaCode
                        ))
                        currentAreaCode += 1
                    }
                }

                if !channels.isEmpty {
                    let splatDesc = NavMeshGenerator.SplatDescriptor(
                        name: "\(splatFile)_splat",
                        image: rotatedSplat,
                        channels: channels
                    )
                    splatDescriptors.append(splatDesc)
                    print("Added splat '\(splatFile)' with \(channels.count) channels")
                }
            }
        }

        // ────────────────────────────────────────────────
        // Build the NavMesh
        // ────────────────────────────────────────────────
        do {
            navMesh = try await NavMeshGenerator.makeNavMesh(
                terrain: terrainSource,
                splats: splatDescriptors, // Will be empty array if no splats
                config: customNavMeshConfig,
                agentHeight: 2.0,
                agentRadius: 0.5,
                agentMaxClimb: 45.0
            )
        } catch {
            print("❌ NavMesh generation failed: \(error)")
            return (nil, nil)
        }

        // ────────────────────────────────────────────────
        // Extract + summarise geometry
        // ────────────────────────────────────────────────
        geometry = navMesh!.extractGeometry(verbose: true)
        let areaCounts = Dictionary(grouping: geometry!.polygons, by: { $0.area })
            .mapValues { $0.count }
        for (area, count) in areaCounts.sorted(by: { $0.key < $1.key }) {
            print("Area code \(area): \(count) polygons")
        }

        // ────────────────────────────────────────────────
        // Export OBJ & BIN
        // ────────────────────────────────────────────────
        let exportBaseURL = URL(fileURLWithPath: exportDirectory, isDirectory: true)

        // • OBJ
        let objURL = exportBaseURL.appendingPathComponent("swiftNavMesh.obj")
        var allVertices: [SIMD3<Float>] = []
        var allIndices: [Int32] = []
        for polygon in geometry!.polygons {
            let baseIndex = Int32(allVertices.count)
            allVertices += polygon.vertices
            for vertexIndex in 1 ..< polygon.vertices.count - 1 {
                allIndices += [baseIndex,
                               baseIndex + Int32(vertexIndex),
                               baseIndex + Int32(vertexIndex + 1)]
            }
        }
        do {
            try OBJParser.write(vertices: allVertices,
                                triangles: allIndices,
                                to: objURL)
            print("✅ NavMesh exported to OBJ at \(objURL.path)")
        } catch {
            print("❌ Failed to export NavMesh OBJ: \(error)")
        }

        // • BIN
        let binURL = exportBaseURL.appendingPathComponent("all_tiles_navmesh.bin")
        do {
            try navMesh!.save(to: binURL)
            print("✅ NavMesh exported to BIN at \(binURL.path)")
        } catch {
            print("❌ Failed to export NavMesh BIN: \(error)")
        }

        // • USDA
        let usdaURL = exportBaseURL.appendingPathComponent("navmesh.usda")
        do {
            try geometry!.exportToUSDA(filePath: usdaURL.path)
            print("✅ NavMesh exported to USDA at \(usdaURL.path)")
        } catch {
            print("❌ Failed to export NavMesh USDA: \(error)")
        }

        let usdaURLtiled = exportBaseURL.appendingPathComponent("navmesh_tiled.usda")
        do {
            try geometry!.exportToUSDATiled(filePath: usdaURLtiled.path)
            print("✅ NavMesh exported to tiled USDA at \(usdaURLtiled.path)")
        } catch {
            print("❌ Failed to export tiled NavMesh USDA: \(error)")
        }
    }

    // ────────────────────────────────────────────────
    // 3️⃣ Visual entities (optional)
    // ────────────────────────────────────────────────
    var navMeshEntity: Entity?
    var terrainEntity: Entity?

    if showNavMesh, let geom = geometry {
        let shouldDrawEdges = geom.polygons.count < 1_000
        navMeshEntity = geom.makeOptimizedNavMeshEntity(
            polygonThreshold: 500,
            showEdges: shouldDrawEdges,
            showTileBounds: false
        )
    }

    if showTerrain {
        switch terrainSource {
        case .model(let name):
            do {
                let modelEntity = try await ModelEntity(named: name, in: .main)
                modelEntity.scale = .one
                // set terrain to red - debug 👀
                let redMat = SimpleMaterial(color: .red, isMetallic: false)
                modelEntity.model?.materials = Array(
                    repeating: redMat,
                    count: modelEntity.model?.materials.count ?? 1
                )

                terrainEntity = modelEntity
                print("✅ Terrain model added")
            } catch {
                print("⚠️ Failed to load terrain model: \(error)")
            }
        case .obj(let path, let scale):
            do {
                let loader = try MeshLoader(file: path)
                var desc = MeshDescriptor()
                desc.positions = .init(loader.vertices)
                desc.primitives = .triangles(loader.triangles.map { UInt32($0) })
                let mesh = try MeshResource.generate(from: [desc])
                let mat = SimpleMaterial(color: .systemGray.withAlphaComponent(0.5), isMetallic: false)
                let modelEntity = ModelEntity(mesh: mesh, materials: [mat])
                modelEntity.scale = SIMD3(repeating: scale)
                terrainEntity = modelEntity
            } catch {
                print("❌ Failed to build terrain entity from OBJ: \(error)")
            }
        }
    }

    // ────────────────────────────────────────────────
    // 4️⃣ Shared transform + camera framing
    // ────────────────────────────────────────────────
    guard showNavMesh || showTerrain else {
        print("⚠️ No visual entities requested (display = .none) – skipping scene insertion.")
        return (navMesh, nil)
    }

    // Compute bounding sphere center & radius
    let (meshCenter, meshRadius): (SIMD3<Float>, Float)
    if let geom = geometry {
        // NavMesh geometry available → use its bounding sphere
        let sphere = geom.boundingSphere()
        meshCenter = sphere.center
        meshRadius = sphere.radius
    } else if let terr = terrainEntity {
        // No NavMesh geometry, but we do have the terrain → use its visualBounds
        let bounds = terr.visualBounds(relativeTo: nil)
        meshCenter = bounds.center
        // extents are full widths; radius is roughly half the diagonal
        meshRadius = length(bounds.extents) * 0.5
    } else {
        // All else failed—fall back to origin + unit radius
        meshCenter = .zero
        meshRadius = 1.0
    }

    let root = Entity()
    if let nav = navMeshEntity {
        nav.name = "NavMesh"
        nav.position = -meshCenter
        nav.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
        root.addChild(nav)
    }
    if let terr = terrainEntity {
        terr.name = "Terrain"
        terr.position = -meshCenter
        terr.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
        root.addChild(terr)
    }
    let verticalFOV: Float = .pi / 3
    let cameraDistance = meshRadius / sin(verticalFOV * 0.5) * 0.5
    root.position = SIMD3(0, 0, -cameraDistance)
    spaceOrigin.addChild(root)
    print("✅ buildFoothillNavMeshExample complete – displayed: \(display)")

    return (navMesh, root)
}

/// Utility for building a Detour NavMesh from an OBJ or RealityKit terrain and one or more splat mask images,
/// each with custom area codes per channel.
public enum NavMeshGenerator {
    /// Defines a splat mask image with one or more channels and associated NavMesh area codes.
    public struct SplatDescriptor {
        public struct ChannelInfo {
            public let channel: SplatMeshGenerator.Channel
            public let areaCode: UInt8
            public init(channel: SplatMeshGenerator.Channel, areaCode: UInt8) {
                self.channel = channel
                self.areaCode = areaCode
            }
        }

        public let name: String
        public let image: UIImage
        public let channels: [ChannelInfo]
        public init(name: String, image: UIImage, channels: [ChannelInfo]) {
            self.name = name
            self.image = image
            self.channels = channels
        }
    }

    /// Specifies the terrain geometry source: either an OBJ file or a RealityKit model by name.
    public enum TerrainSource {
        /// Load from OBJ file path, with optional uniform scale.
        case obj(path: String, scale: Float = 1.0)
        /// Load from a RealityKit asset name.
        case model(name: String)
    }

    /// Builds a NavMesh by projecting each splat channel onto the terrain and marking areas accordingly.
    public static func makeNavMesh(
        terrain: TerrainSource,
        splats: [SplatDescriptor],
        maxEdgeLength: CGFloat = 50,
        simplificationTolerance: CGFloat = 0.001,
        threshold: Float? = 0.1,
        invertMask: Bool? = false,
        morphologyRadius: Int = 0,
        interiorSpacingFactor: CGFloat = 1_000,
        config: NavMeshConfig,
        agentHeight: Float,
        agentRadius: Float,
        agentMaxClimb: Float
    ) async throws -> NavMesh {
        // 1️⃣ Load main terrain mesh (OBJ or RealityKit) and store for projection
        let mainVertices: [SIMD3<Float>]
        let mainTriangles: [Int32]
        var loadedTerrainEntity: ModelEntity? = nil
        let mainMeshLoader: MeshLoader
        let terrainDesc: String

        switch terrain {
        case .obj(let path, let scale):
            terrainDesc = "OBJ(\"\(path)\", scale: \(scale))"
            let loader = try MeshLoader(file: path)
            mainVertices = loader.vertices
            mainTriangles = loader.triangles
            mainMeshLoader = loader
        case .model(let name):
            terrainDesc = "Model(\"\(name)\")"

            let entity = try await ModelEntity(named: name, in: .main)
            loadedTerrainEntity = entity
            guard let modelComponent = await entity.model else {
                throw NSError(
                    domain: "NavMeshGenerator",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "ModelEntity has no ModelComponent"]
                )
            }
            var flatVerts = [Float]()
            var rawTris = [Int32]()
            for meshModel in await modelComponent.mesh.contents.models {
                for part in meshModel.parts {
                    if let positions = part.buffers[.positions]?.get(SIMD3<Float>.self) {
                        flatVerts = []
                        flatVerts.reserveCapacity(positions.count * 3)
                        for v in positions {
                            flatVerts += [v.x, v.y, v.z]
                        }
                    }
                    if let tri16 = part.buffers[.triangleIndices]?.get(UInt16.self) {
                        rawTris = tri16.elements.map { Int32($0) }
                    } else if let tri32 = part.buffers[.triangleIndices]?.get(UInt32.self) {
                        rawTris = tri32.elements.map { Int32($0) }
                    }
                }
            }
            mainVertices = stride(from: 0, to: flatVerts.count, by: 3).map {
                SIMD3<Float>(flatVerts[$0], flatVerts[$0 + 1], flatVerts[$0 + 2])
            }
            mainTriangles = rawTris
            // Convert Int32 → UInt32 for MeshLoader API
            let indexUInts = rawTris.map { UInt32($0) }
            mainMeshLoader = MeshLoader(vertices3D: mainVertices, indices: indexUInts)
        }
        print("[NavMeshGenerator] Loaded main mesh for terrain \(terrainDesc) → vertices: \(mainMeshLoader.vertices.count), triangles: \(mainMeshLoader.triangles.count)")

        // 2️⃣ Generate area definitions per splat channel
        var areaDefinitions = [AreaDefinition]()
        for descriptor in splats {
            for channelInfo in descriptor.channels {
                print("[NavMeshGenerator] Processing splat '\(descriptor.name)' channel: \(channelInfo.channel) areaCode: \(channelInfo.areaCode)")

                // 2a: Generate 2D mesh for this channel
                let mesh2D = try await SplatMeshGenerator(
                    maxEdgeLength: maxEdgeLength,
                    simplificationTolerance: simplificationTolerance,
                    threshold: threshold,
                    channel: channelInfo.channel,
                    invertMask: invertMask,
                    morphologyRadius: morphologyRadius,
                    interiorSpacingFactor: interiorSpacingFactor
                ).mesh(from: descriptor.image)
                let triCount2D = mesh2D.indices.count / 3
                print(
                    "[NavMeshGenerator] 2D mesh generated → " +
                        "vertices: \(mesh2D.vertices.count), " +
                        "triangles: \(triCount2D)"
                )
                // 2b: Project into 3D on same terrain
                let channelLoader: MeshLoader
                switch terrain {
                case .obj(let path, let scale):
                    channelLoader = try MeshLoader(
                        splatMesh2D: mesh2D,
                        terrainOBJPath: path,
                        terrainScale: scale,
                        debugPrint: true
                    )
                case .model:
                    guard let entity = loadedTerrainEntity else {
                        fatalError("Terrain entity not loaded for .model projection")
                    }
                    channelLoader = MeshLoader(
                        splatMesh2D: mesh2D,
                        terrainModel: entity,
                        debugPrint: true
                    )
                }
                print(
                    "[NavMeshGenerator] Channel mesh projected → " +
                        "vertices: \(channelLoader.vertices.count), " +
                        "triangles: \(channelLoader.triangles.count)"
                )

                let areaDef = AreaDefinition(
                    vertices: channelLoader.vertices,
                    triangles: channelLoader.triangles,
                    areaCode: channelInfo.areaCode
                )
                areaDefinitions.append(areaDef)
                print(
                    "[NavMeshGenerator] Added AreaDefinition → " +
                        "vertices: \(areaDef.vertices.count), " +
                        "triangles: \(areaDef.triangles.count), " +
                        "code: \(areaDef.areaCode)"
                )
            }
        }

        // 3️⃣ Build final NavMesh; if no splats, use default initializer
        print(
            "[NavMeshGenerator] Initializing NavMeshBuilder → " +
                "main mesh vtx: \(mainMeshLoader.vertices.count), " +
                "tris: \(mainMeshLoader.triangles.count), " +
                "areaDefs: \(areaDefinitions.count)"
        )

        let builder: NavMeshBuilder
        if areaDefinitions.isEmpty {
            builder = try NavMeshBuilder(
                vertices: mainVertices,
                triangles: mainTriangles,
                config: config
            )
        } else {
            // Debug the area definitions
            let testBuilder = try NavMeshBuilder(
                vertices: mainVertices,
                triangles: mainTriangles,
                config: config,
                areas: [] // Empty for bounds calculation
            )
            testBuilder.debugAreaDefinitions(areaDefinitions)

            builder = try NavMeshBuilder(
                vertices: mainVertices,
                triangles: mainTriangles,
                config: config,
                areas: areaDefinitions
            )
        }
        print("\n[NavMeshGenerator] NavMeshBuilder initialized successfully")

        let navMesh = try builder.makeNavMesh()
        print("[NavMeshGenerator] NavMesh generation complete")
        return navMesh
    }
}
