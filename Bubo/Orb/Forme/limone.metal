#include "../OrbShading.h"

// Salute · movimento: a lemon, an oval with a point at each end, and a leaf on top.
static float limone(float3 p, float) {
    p.y += 0.12;
    float body = sdSegment(p, float3(-0.3, 0, 0), float3(0.3, 0, 0), 0.4);
    float tips = min(sdRoundCone(p, float3(0.5, 0, 0), float3(0.82, 0, 0), 0.3, 0.07),
                     sdRoundCone(p, float3(-0.5, 0, 0), float3(-0.82, 0, 0), 0.3, 0.07));
    float3 q = p - float3(0, 0.36, 0);
    q.xy = q.xy * rot(-0.5);
    float leaf = extrude(sdQuad2(q.xy, float2(0, 0), float2(0.25, 0.15), float2(0.55, 0.08), float2(0.25, -0.06)), q.z, 0.02) - 0.02;
    return min(min(body, tips), leaf);
}

ORB_FORMA(limone)
