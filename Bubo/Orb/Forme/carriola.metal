#include "../OrbShading.h"

// Codice: a wheelbarrow in profile: tray, front wheel, two handles and a leg.
static float carriola(float3 p, float) {
    p.xy += float2(-0.06, -0.25);
    float2 q = p.xy;
    float d = sdQuad2(q, float2(-0.5, 0.15), float2(0.35, 0.15), float2(0.2, -0.2), float2(-0.35, -0.2));
    d = min(d, length(q - float2(0.55, -0.42)) - 0.24);
    d = min(d, udSegment2(q, float2(-0.3, -0.12), float2(-0.9, 0.06)) - 0.05);
    d = min(d, udSegment2(q, float2(-0.35, -0.15), float2(-0.45, -0.66)) - 0.05);
    d = min(d, udSegment2(q, float2(0.25, -0.2), float2(0.55, -0.42)) - 0.05);
    return extrude(d, p.z, 0.10) - 0.03;
}

ORB_FORMA(carriola)
