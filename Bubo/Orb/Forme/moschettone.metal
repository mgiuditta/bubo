#include "../OrbShading.h"

// Salute · arrampicata: a D-shaped carabiner whose straight gate swings open and shut on its hinge.
static float moschettone(float3 p, float t) {
    p.x -= 0.0;
    const float r = 0.07;
    const float2 pts[6] = { float2(-0.4, -0.8), float2(0.15, -0.8), float2(0.48, -0.4), float2(0.48, 0.2), float2(0.2, 0.68), float2(-0.4, 0.78) };
    float d = 9.0;
    for (int i = 0; i < 5; i++) d = min(d, sdSegment(p, float3(pts[i], 0), float3(pts[i + 1], 0), r));
    d = min(d, sdSegment(p, float3(-0.4, -0.8, 0), float3(-0.4, -0.55, 0), r));
    d = min(d, sdSegment(p, float3(-0.4, 0.55, 0), float3(-0.4, 0.78, 0), r));
    float3 g = p - float3(-0.4, -0.55, 0.0);
    g.xy = g.xy * rot(-0.4 * (0.5 + 0.5 * sin(t * 1.5)));
    float gate = sdSegment(g, float3(0, 0, 0), float3(0, 1.1, 0), 0.06);
    float hinge = length(g) - 0.09;
    return min(d, min(gate, hinge));
}

ORB_FORMA(moschettone)
