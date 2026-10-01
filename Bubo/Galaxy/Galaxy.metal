// The Galassia's map (spec 11): folders as rings and points, files as stars, all instanced quads.
// The level of detail is worked out here from the camera, so moving the map changes only the uniforms.

#include <metal_stdlib>
using namespace metal;

/// One folder or file; the same layout as `GalaxyInstance` in Swift.
struct GalaxyInstance {
    float2 position;
    /// Folders: their radius on the plane. Stars: the room each star has. Selection: its radius in points.
    float radius;
    /// Folders: their number of files. Stars: their folder's radius on the plane.
    float value;
    /// Stars: 1 for a search result, 2 for the selected file.
    uint flags;
    uint depth;
};

/// The same layout as `GalaxyUniforms` in Swift.
struct GalaxyUniforms {
    float2 center;
    float2 viewport;
    float scale;
    float tilt;
    float pixelsPerPoint;
    float starsAppear;
    float starsShown;
    uint isSearching;
};

struct GalaxyFragment {
    float4 position [[position]];
    /// The quad's corner, scaled so the shape's edge is at length 1.
    float2 corner;
    /// The shape's radius in pixels, for anti-aliasing.
    float pixelRadius;
    float alpha;
};

constant float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
/// Palette.textPrimary.
constant float3 starlight = float3(0.957, 0.922, 0.894);
constant uint searchResult = 1;
constant uint selected = 2;

static float2 screenPoint(float2 plane, constant GalaxyUniforms &u) {
    return u.viewport / 2 + (plane - u.center) * float2(u.scale, u.scale * u.tilt);
}

static float4 clipPosition(float2 point, constant GalaxyUniforms &u) {
    float2 ndc = point / u.viewport * 2 - 1;
    return float4(ndc.x, -ndc.y, 0, 1);
}

/// A quad of `radii` points around `center`, one point larger for the anti-aliased edge.
static GalaxyFragment billboard(float2 center, float2 radii, float alpha, uint vertexID, constant GalaxyUniforms &u) {
    float2 corner = corners[vertexID];
    float2 padded = radii + 1;
    GalaxyFragment out;
    out.position = clipPosition(center + corner * padded, u);
    out.corner = corner * padded / radii;
    out.pixelRadius = radii.x * u.pixelsPerPoint;
    out.alpha = alpha;
    return out;
}

/// The outline of a folder, readable once it is large enough on screen; the Progetto itself has none.
vertex GalaxyFragment galaxy_ring_vertex(uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
                                         constant GalaxyInstance *instances [[buffer(0)]],
                                         constant GalaxyUniforms &u [[buffer(1)]]) {
    GalaxyInstance folder = instances[instanceID];
    float radius = folder.radius * u.scale;
    float alpha = folder.depth == 0 ? 0
        : folder.depth == 1 ? 0.16 * smoothstep(16.0, 30.0, radius)
        : 0.10 * smoothstep(30.0, 60.0, radius);
    return billboard(screenPoint(folder.position, u), float2(radius, radius * u.tilt), alpha, vertexID, u);
}

/// A folder seen from far away: one point, larger with more files, gone once its stars show.
vertex GalaxyFragment galaxy_point_vertex(uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
                                          constant GalaxyInstance *instances [[buffer(0)]],
                                          constant GalaxyUniforms &u [[buffer(1)]]) {
    GalaxyInstance folder = instances[instanceID];
    float radius = folder.radius * u.scale;
    float size = clamp(1 + 0.55 * log2(1 + folder.value), 1.0, 4.5);
    float alpha = folder.depth == 0 || folder.value == 0 ? 0
        : 0.55 * smoothstep(1.5, 4.0, radius) * (1 - smoothstep(u.starsAppear, u.starsShown, radius));
    return billboard(screenPoint(folder.position, u), float2(size), alpha, vertexID, u);
}

/// A file: shown once its folder is large enough, always when it is a search result or selected.
vertex GalaxyFragment galaxy_star_vertex(uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
                                         constant GalaxyInstance *instances [[buffer(0)]],
                                         constant GalaxyUniforms &u [[buffer(1)]]) {
    GalaxyInstance star = instances[instanceID];
    float size = clamp(star.radius * u.scale * 0.22, 0.6, 1.6);
    float alpha = 0.42 * smoothstep(u.starsAppear, u.starsShown, star.value * u.scale);
    if (u.isSearching != 0) { alpha *= 0.4; }
    if ((star.flags & searchResult) != 0) {
        alpha = 0.95;
        size += 0.8;
    }
    if ((star.flags & selected) != 0) {
        alpha = 1;
        size = max(size, 2.2);
    }
    return billboard(screenPoint(star.position, u), float2(size), alpha, vertexID, u);
}

/// The ring around the selected file, the same size whatever the zoom.
vertex GalaxyFragment galaxy_selection_vertex(uint vertexID [[vertex_id]],
                                              constant GalaxyInstance *instances [[buffer(0)]],
                                              constant GalaxyUniforms &u [[buffer(1)]]) {
    GalaxyInstance star = instances[0];
    return billboard(screenPoint(star.position, u), float2(star.radius), 0.9, vertexID, u);
}

/// A one-point outline at the edge of the quad's shape.
fragment float4 galaxy_ring_fragment(GalaxyFragment in [[stage_in]], constant GalaxyUniforms &u [[buffer(1)]]) {
    float distance = abs(length(in.corner) - 1) * in.pixelRadius;
    float alpha = in.alpha * (1 - smoothstep(0.5 * u.pixelsPerPoint, 0.5 * u.pixelsPerPoint + 1, distance));
    return float4(starlight * alpha, alpha);
}

/// A filled disc with a soft edge.
fragment float4 galaxy_disc_fragment(GalaxyFragment in [[stage_in]]) {
    float alpha = in.alpha * saturate((1 - length(in.corner)) * in.pixelRadius + 0.5);
    return float4(starlight * alpha, alpha);
}
