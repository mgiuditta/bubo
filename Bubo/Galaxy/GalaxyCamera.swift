import Foundation

/// The view on the Galassia's plane: an orthographic camera looking down at a tilt, so the plane reads as 2.5D and
/// every ammasso is an ellipse.
nonisolated struct GalaxyCamera: Equatable, Sendable {
    /// The plane point at the middle of the view.
    var center: SIMD2<Float> = .zero
    /// Points of the view per unit of the plane.
    var scale: Float = 1

    /// How much the tilt flattens the plane's depth: the cosine of a 35° look.
    static let tilt: Float = 0.82
    /// The closest the camera gets, in points per unit: a core disc 8000 points wide.
    static let maximumScale: Float = 4_000

    /// The point of the view, `size` large, where `plane` shows.
    func point(for plane: SIMD2<Float>, in size: CGSize) -> CGPoint {
        CGPoint(x: Double(Float(size.width) / 2 + (plane.x - center.x) * scale),
                y: Double(Float(size.height) / 2 + (plane.y - center.y) * scale * Self.tilt))
    }

    /// The plane point under `point` of the view, `size` large.
    func plane(at point: CGPoint, in size: CGSize) -> SIMD2<Float> {
        SIMD2(center.x + (Float(point.x) - Float(size.width) / 2) / scale,
              center.y + (Float(point.y) - Float(size.height) / 2) / (scale * Self.tilt))
    }

    /// The camera that shows the whole circle of `radius` around `center` in a view `size` large, with a margin.
    static func fitting(radius: Float, around center: SIMD2<Float> = .zero, in size: CGSize) -> GalaxyCamera {
        let room = min(Float(size.width), Float(size.height) / tilt)
        let scale = room > 0 && radius > 0 ? room * 0.46 / radius : 1
        return GalaxyCamera(center: center, scale: min(scale, maximumScale))
    }

    /// Moves the plane by `translation` points of the view, as a drag does.
    mutating func pan(by translation: CGSize) {
        center.x -= Float(translation.width) / scale
        center.y -= Float(translation.height) / (scale * Self.tilt)
    }

    /// Zooms by `factor`, keeping the plane point under `anchor` where it is, between `minimumScale` and
    /// ``maximumScale``.
    mutating func zoom(by factor: Float, around anchor: CGPoint, in size: CGSize, minimumScale: Float) {
        let fixed = plane(at: anchor, in: size)
        scale = min(max(scale * factor, minimumScale), Self.maximumScale)
        let moved = plane(at: anchor, in: size)
        center += fixed - moved
    }

    /// The camera `progress` of the way from `start` to `end`, eased in and out; the zoom moves evenly in log scale.
    static func interpolated(from start: GalaxyCamera, to end: GalaxyCamera, progress: Double) -> GalaxyCamera {
        let t = Float(min(max(progress, 0), 1))
        // Exactly at the end once there, whatever the rounding on the way.
        guard t < 1 else { return end }
        let eased = t < 0.5 ? 2 * t * t : 1 - (2 - 2 * t) * (2 - 2 * t) / 2
        return GalaxyCamera(center: start.center + (end.center - start.center) * eased,
                            scale: start.scale * pow(end.scale / start.scale, eased))
    }
}
