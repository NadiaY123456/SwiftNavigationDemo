import RealityKit
import simd
import SwiftNavigation
import UIKit

// MARK: - Example Visualization

/// Example function to build a NavMesh for the “foothill” model and visualize it under a given scene origin.
@MainActor
public func buildFoothillNavMeshExample(on spaceOrigin: Entity) async {
    // 1️⃣ Define the terrain source (RealityKit model "foothill" in the bundle's Data folder)
    // from usdz
    let terrainName = "foothillUSDZ"
//    let terrainName = "foothillUSDZ"
    let terrainSource = NavMeshGenerator.TerrainSource.model(
        name: terrainName,
        rotation: simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
    )
    print("Using terrain: \(terrainName)")

//    // from obj
//    let file = "plane.obj"
    ////    let file = "splatRed.obj"
//    let objPath = "/Users/nata/GitHub/Practicing/SwiftNavigationDemo/NavMeshDemo/Data/\(file)"
//    let terrainSource = NavMeshGenerator.TerrainSource.obj(
//        path: objPath,
//        scale: 1.0
//    )

    // 2️⃣ Load splat image (if using splats)
    let imageName = "splat_rgba"
    guard let splat = UIImage(named: imageName) else {
        print("❌ Failed to load image “\(imageName)”")
        return
    }
    // Example channels (green = road, blue = water)
    let roadChannel = NavMeshGenerator.SplatDescriptor.ChannelInfo(channel: .green, areaCode: 2)
    let waterChannel = NavMeshGenerator.SplatDescriptor.ChannelInfo(channel: .blue, areaCode: 3)
    let splatDesc = NavMeshGenerator.SplatDescriptor(
        name: "foothillSplat",
        image: splat,
        channels: [waterChannel, roadChannel]
    )

    // 3️⃣ Build the NavMesh (no splats = just terrain navmesh)
    let navMesh: NavMesh
    do {
        navMesh = try await NavMeshGenerator.makeNavMesh(
            terrain: terrainSource,
            splats: [splatDesc],
            config: customNavMeshConfig,
            agentHeight: 2.0,
            agentRadius: 0.5,
            agentMaxClimb: 45.0
        )
    } catch {
        print("NavMesh generation failed: \(error)")
        return
    }

    // 4️⃣ Extract geometry
    let geometry = navMesh.extractGeometry(verbose: true)

    // Summarize geometry by area
    let areaCounts = Dictionary(grouping: geometry.polygons, by: { $0.area })
        .mapValues { $0.count }

    // Print sorted by area code
    for (area, count) in areaCounts.sorted(by: { $0.key < $1.key }) {
        print("Area code \(area): \(count) polygons")
    }

    //  Export NavMesh as OBJ
    let exportPath = "/Users/nata/Library/CloudStorage/OneDrive-Personal/CNC/VisionPro/World/swiftNavMesh.obj"
    let exportURL = URL(fileURLWithPath: exportPath)

    do {
        var allVertices: [SIMD3<Float>] = []
        var allIndices: [Int32] = []

        // Flatten every polygon, fan-triangulating it
        for poly in geometry.polygons {
            let baseIndex = Int32(allVertices.count)
            allVertices += poly.vertices

            let vCount = poly.vertices.count
            for i in 1 ..< vCount - 1 {
                allIndices += [
                    baseIndex,
                    baseIndex + Int32(i),
                    baseIndex + Int32(i + 1)
                ]
            }
        }

        try OBJParser.write(vertices: allVertices,
                            triangles: allIndices,
                            to: exportURL)
        print("✅ NavMesh exported to OBJ at \(exportPath)")
    } catch {
        print("❌ Failed to export NavMesh OBJ: \(error)")
    }
    // 5️⃣ Create visualizer entity
    let navEntity = geometry.makeNavMeshEntity(
        showEdges: true
    )

    // 6️⃣ Position & scale
//    let scale: Float = 0.1
//    let height: Float = -0
//    let zDistance: Float = -100
//    navEntity.position.y += height
//    navEntity.position.z += zDistance
//    navEntity.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
//    navEntity.scale = SIMD3<Float>(scale, scale, scale)

    // 7️⃣ Add to scene origin
    spaceOrigin.addChild(navEntity)
    print("✅ NavMesh visualized under spaceOrigin")

//    // 8️⃣ (Optional) Load and add the USDZ terrain model
//    do {
//        let modelEntity = try await ModelEntity(named: "foothill", in: .main)
//        modelEntity.scale = .one
//        spaceOrigin.addChild(modelEntity)
//        print("✅ Terrain model added")
//    } catch {
//        print("⚠️ Failed to load terrain model: \(error)")
//    }
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
        /// Load from a RealityKit asset name, applying rotation when sampling heights.
        case model(name: String, rotation: simd_quatf = simd_quatf(angle: .pi / 2, axis: [0, 1, 0]))
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
        interiorSpacingFactor: CGFloat = 1000,
        config: NavMeshConfig,
        agentHeight: Float,
        agentRadius: Float,
        agentMaxClimb: Float
    ) async throws -> NavMesh {
        // 1️⃣ Load main terrain mesh (OBJ or RealityKit) and store for projection
        let mainVertices: [SIMD3<Float>]
        let mainTriangles: [Int32]
        var loadedTerrainEntity: ModelEntity? = nil
        var terrainRotation: simd_quatf? = nil
        let mainMeshLoader: MeshLoader
        let terrainDesc: String

        switch terrain {
        case .obj(let path, let scale):
            terrainDesc = "OBJ(\"\(path)\", scale: \(scale))"
            let loader = try MeshLoader(file: path)
            mainVertices = loader.vertices
            mainTriangles = loader.triangles
            mainMeshLoader = loader
        case .model(let name, let rotation):
            terrainDesc = "Model(\"\(name)\")"

            terrainRotation = rotation
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
                        terrainScale: scale
                    )
                case .model:
                    guard let entity = loadedTerrainEntity,
                          let rotation = terrainRotation
                    else {
                        fatalError("Terrain entity not loaded for .model projection")
                    }
                    channelLoader = MeshLoader(
                        splatMesh2D: mesh2D,
                        terrainModel: entity,
                        terrainRotation: rotation
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
                areas: []  // Empty for bounds calculation
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
