import Foundation

enum ClothoidQuadrature {
    // Gauss-Legendre positive half-nodes/weights. 4-vs-8 comparison controls error.
    private static let nodes8 = [0.1834346424956498, 0.5255324099163290, 0.7966664774136267, 0.9602898564975363]
    private static let weights8 = [0.3626837833783620, 0.3137066458778873, 0.2223810344533745, 0.1012285362903763]
    private static let nodes4 = [0.3399810435848563, 0.8611363115940526]
    private static let weights4 = [0.6521451548625461, 0.3478548451374538]
    static func integrate(from a: Double, to b: Double, heading: Double, k0: Double,
                          rate: Double, tolerance: Double, depth: Int = 0) throws -> Vector2 {
        if b <= a { return Vector2(x: 0, y: 0) }
        func quadrature(_ nodes: [Double], _ weights: [Double]) -> Vector2 {
            let mid = (a + b) / 2; let half = (b - a) / 2
            var x = 0.0; var y = 0.0
            for i in nodes.indices {
                for sign in [-1.0, 1.0] {
                    let s = mid + sign * half * nodes[i]
                    let theta = heading + k0 * s + rate * s * s / 2
                    x += weights[i] * cos(theta); y += weights[i] * sin(theta)
                }
            }
            return Vector2(x: x * half, y: y * half)
        }
        let fine = quadrature(nodes8, weights8); let coarse = quadrature(nodes4, weights4)
        let floor = 32 * Double.ulpOfOne * (b - a)
        if hypot(fine.x - coarse.x, fine.y - coarse.y) <= max(tolerance, floor) { return fine }
        guard depth < 24 else { throw GeometryError.numericalFailure("Clothoid quadrature did not converge.") }
        let mid = (a + b) / 2
        let left = try integrate(from: a, to: mid, heading: heading, k0: k0, rate: rate, tolerance: tolerance / 2, depth: depth + 1)
        let right = try integrate(from: mid, to: b, heading: heading, k0: k0, rate: rate, tolerance: tolerance / 2, depth: depth + 1)
        return Vector2(x: left.x + right.x, y: left.y + right.y)
    }
}
