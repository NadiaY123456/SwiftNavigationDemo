//
//  TestCrowd.swift
//  NavMeshDemo
//
//  Created by Nadia Yilmaz on 6/22/25.
//


#if false

func testCrowd() throws {
    let data = try ObjMeshLoader(file: "/Users/nata/GitHub/Practicing/recastnavigation/RecastDemo/Bin/Meshes/dungeon.obj")
    let config = NavMeshBuilder.Config(partitionStyle: .monotone)
    let builder = try NavMeshBuilder(vertices: data.vertices, triangles: data.triangles, config: config)
    let navigator = try builder.makeNavMesh(agentHeight: 1, agentRadius: 0.3, agentMaxClimb: 20)
    let query = try navigator.makeQuery()

    let end = try query.findRandomPoint(randomFunction: fakeRandom).get()
    print("Target is: \(end)")

    let crowd = try navigator.makeCrowd(maxAgents: 16, agentRadius: 0.3)
    var agents: [CrowdAgent] = []
    for _ in 0..<4 {
        let agentStart = try query.findRandomPoint(randomFunction: fakeRandom).get()
        guard let agent = crowd.addAgent(agentStart.point3) else { continue }
        agents.append(agent)
        agent.requestMove(target: end)
    }
    for x in stride(from: 0.0, to: 3.0, by: 0.01) {
        crowd.update(dt: Float(x))
        for x in 0..<agents.count {
            print("\(x): \(agents[x].position)")
        }
    }
}
#endif
