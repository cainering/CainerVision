import Foundation
import RealityKit
import simd

enum ProceduralMesh {
    static func torus(meanRadius: Float, tubeRadius: Float, sides: Int = 40, tubeSides: Int = 18) throws -> MeshResource {
        guard meanRadius > 0, tubeRadius > 0, sides >= 3, tubeSides >= 3 else {
            throw UserFacingError(message: "Couldn't build that ring.")
        }
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(sides * tubeSides)
        for side in 0..<sides {
            let theta = Float(side) / Float(sides) * 2 * .pi
            let cosTheta = cos(theta)
            let sinTheta = sin(theta)
            let center = SIMD3<Float>(cosTheta * meanRadius, 0, sinTheta * meanRadius)
            for tube in 0..<tubeSides {
                let phi = Float(tube) / Float(tubeSides) * 2 * .pi
                let cosPhi = cos(phi)
                let sinPhi = sin(phi)
                let normal = SIMD3<Float>(cosTheta * cosPhi, sinPhi, sinTheta * cosPhi)
                positions.append(center + normal * tubeRadius)
                normals.append(simd_normalize(normal))
            }
        }

        func vertex(_ side: Int, _ tube: Int) -> UInt32 {
            let wrappedSide = (side % sides + sides) % sides
            let wrappedTube = (tube % tubeSides + tubeSides) % tubeSides
            return UInt32(wrappedSide * tubeSides + wrappedTube)
        }

        for side in 0..<sides {
            for tube in 0..<tubeSides {
                let a = vertex(side, tube)
                let b = vertex(side + 1, tube)
                let c = vertex(side + 1, tube + 1)
                let d = vertex(side, tube + 1)
                let edge1 = positions[Int(b)] - positions[Int(a)]
                let edge2 = positions[Int(d)] - positions[Int(a)]
                let facing = simd_dot(simd_cross(edge1, edge2), normals[Int(a)])
                if facing >= 0 {
                    indices.append(contentsOf: [a, b, c, a, c, d])
                } else {
                    indices.append(contentsOf: [a, d, c, a, c, b])
                }
            }
        }

        var descriptor = MeshDescriptor(name: "torus")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}
