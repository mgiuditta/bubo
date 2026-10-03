// The Neuroni's map: the notes as discs colored by folder, their links as thin lines, all instanced quads as in the
// Galassia. The links read the notes' places from the nodes' buffer, so moving a note rewrites only that buffer.

#include <metal_stdlib>
using namespace metal;

/// One note; the same layout as `NeuronNode` in Swift.
struct NeuronNode {
    float2 position;
    /// Its radius on the plane.
    float radius;
    /// Its folder's color, as RGBA bytes.
    uint color;
    /// 1 when the folder filter or the search leaves it out.
    uint flags;
};

/// The same layout as `NeuronUniforms` in Swift.
struct NeuronUniforms {
    float2 center;
    float2 viewport;
    float scale;
    float pixelsPerPoint;
    /// The selected note, or 0xFFFFFFFF.
    uint selected;
};

struct NeuronFragment {
    float4 position [[position]];
    /// The quad's corner, scaled so the shape's edge is at length 1.
    float2 corner;
    /// The shape's radius in pixels, for anti-aliasing.
    float pixelRadius;
    float4 color;
};

constant float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
constant uint hidden = 1;
/// Palette.textPrimary.
constant float3 moonlight = float3(0.925, 0.933, 0.945);
/// Half the width of a link, in points.
constant float linkHalfWidth = 0.6;

static float2 screenPoint(float2 plane, constant NeuronUniforms &u) {
    return u.viewport / 2 + (plane - u.center) * u.scale;
}

static float4 clipPosition(float2 point, constant NeuronUniforms &u) {
    float2 ndc = point / u.viewport * 2 - 1;
    return float4(ndc.x, -ndc.y, 0, 1);
}

/// A note: a disc of its folder's color, faint when left out.
vertex NeuronFragment neuron_node_vertex(uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
                                         constant NeuronNode *nodes [[buffer(0)]],
                                         constant NeuronUniforms &u [[buffer(1)]]) {
    NeuronNode node = nodes[instanceID];
    float radius = max(node.radius * u.scale, 1.5);
    float2 corner = corners[vertexID];
    float padded = radius + 1;
    NeuronFragment out;
    out.position = clipPosition(screenPoint(node.position, u) + corner * padded, u);
    out.corner = corner * padded / radius;
    out.pixelRadius = radius * u.pixelsPerPoint;
    float alpha = (node.flags & hidden) != 0 ? 0.12 : 0.95;
    out.color = float4(unpack_unorm4x8_to_float(node.color).rgb, alpha);
    return out;
}

/// A link between two notes: faint, brighter around the selected note, almost gone when a note is left out.
vertex NeuronFragment neuron_link_vertex(uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
                                         constant uint2 *links [[buffer(0)]],
                                         constant NeuronUniforms &u [[buffer(1)]],
                                         constant NeuronNode *nodes [[buffer(2)]]) {
    uint2 link = links[instanceID];
    NeuronNode a = nodes[link.x];
    NeuronNode b = nodes[link.y];
    float2 from = screenPoint(a.position, u);
    float2 to = screenPoint(b.position, u);
    float2 along = to - from;
    float2 direction = length(along) > 0.001 ? normalize(along) : float2(1, 0);
    float2 normal = float2(-direction.y, direction.x);
    float2 corner = corners[vertexID];
    float padded = linkHalfWidth + 1;
    NeuronFragment out;
    out.position = clipPosition(mix(from, to, (corner.x + 1) / 2) + normal * corner.y * padded, u);
    out.corner = float2(0, corner.y * padded / linkHalfWidth);
    out.pixelRadius = linkHalfWidth * u.pixelsPerPoint;
    float alpha = link.x == u.selected || link.y == u.selected ? 0.7 : 0.14;
    if (((a.flags | b.flags) & hidden) != 0) { alpha = 0.03; }
    out.color = float4(moonlight, alpha);
    return out;
}

/// A ring around a note, a few points out: the selected note and those cited in the last answer.
vertex NeuronFragment neuron_ring_vertex(uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
                                         constant NeuronNode *nodes [[buffer(0)]],
                                         constant NeuronUniforms &u [[buffer(1)]]) {
    NeuronNode node = nodes[instanceID];
    float radius = max(node.radius * u.scale, 1.5) + 3.5;
    float2 corner = corners[vertexID];
    float padded = radius + 1;
    NeuronFragment out;
    out.position = clipPosition(screenPoint(node.position, u) + corner * padded, u);
    out.corner = corner * padded / radius;
    out.pixelRadius = radius * u.pixelsPerPoint;
    out.color = float4(moonlight, (node.flags & hidden) != 0 ? 0.3 : 0.9);
    return out;
}

/// A filled disc with a soft edge.
fragment float4 neuron_disc_fragment(NeuronFragment in [[stage_in]]) {
    float alpha = in.color.a * saturate((1 - length(in.corner)) * in.pixelRadius + 0.5);
    return float4(in.color.rgb * alpha, alpha);
}

/// A one-point outline at the edge of the quad's shape.
fragment float4 neuron_ring_fragment(NeuronFragment in [[stage_in]], constant NeuronUniforms &u [[buffer(1)]]) {
    float distance = abs(length(in.corner) - 1) * in.pixelRadius;
    float alpha = in.color.a * (1 - smoothstep(0.5 * u.pixelsPerPoint, 0.5 * u.pixelsPerPoint + 1, distance));
    return float4(in.color.rgb * alpha, alpha);
}

/// A line with soft edges across its width.
fragment float4 neuron_link_fragment(NeuronFragment in [[stage_in]]) {
    float alpha = in.color.a * saturate((1 - abs(in.corner.y)) * in.pixelRadius + 0.5);
    return float4(in.color.rgb * alpha, alpha);
}
