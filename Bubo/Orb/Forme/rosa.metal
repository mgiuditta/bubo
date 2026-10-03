#include "../OrbShading.h"

// A leaf growing from `root` toward +x, mirrored by the caller.
static float rosaLeaf(float3 p, float3 root) {
    float2 q = p.xy - root.xy;
    float shape = sdQuad2(q, float2(0, 0), float2(0.22, 0.14), float2(0.5, 0.08), float2(0.22, -0.07));
    return extrude(shape, p.z, 0.03) - 0.03;
}

// Creativo: a rose, a bloom of five petals around a heart, a bent stem and two leaves.
static float rosa(float3 p, float) {
    float bloom = length(p - float3(0, 0.4, 0.1)) - 0.3;
    bloom = min(bloom, length(p - float3(-0.26, 0.30, 0)) - 0.2);
    bloom = min(bloom, length(p - float3(0.26, 0.30, 0)) - 0.2);
    bloom = min(bloom, length(p - float3(-0.15, 0.62, 0)) - 0.2);
    bloom = min(bloom, length(p - float3(0.15, 0.62, 0)) - 0.2);
    bloom = min(bloom, length(p - float3(0, 0.16, 0)) - 0.2);
    float stem = min(sdSegment(p, float3(0, 0.15, 0), float3(0.04, -0.4, 0), 0.04),
                     sdSegment(p, float3(0.04, -0.4, 0), float3(-0.04, -0.85, 0), 0.04));
    float leaves = min(rosaLeaf(p, float3(0.03, -0.35, 0)),
                       rosaLeaf(float3(-p.x, p.y, p.z), float3(0.03, -0.55, 0)));
    return min(bloom, min(stem, leaves));
}

ORB_FORMA(rosa)
