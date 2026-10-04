#include "../OrbShading.h"

// Viaggi: an airliner seen from above, heading up to the right, rolling gently.
static float aereo(float3 p, float t) {
    p.xy = p.xy * rot(-M_PI_F * 0.25);                 // nose along +y
    p.y -= 0.04 * sin(t * 0.8);
    p.xz = p.xz * rot(0.18 * sin(t * 0.7));
    float3 q = float3(abs(p.x), p.y, p.z);
    float body = sdSegment(p, float3(0, -0.70, 0), float3(0, 0.68, 0), 0.11);
    float wing = extrude(sdQuad2(q.xy, float2(0.08, 0.22), float2(0.86, -0.14), float2(0.86, -0.27), float2(0.08, -0.12)),
                         q.z, 0.01) - 0.02;
    float tail = extrude(sdQuad2(q.xy, float2(0.06, -0.48), float2(0.34, -0.68), float2(0.34, -0.77), float2(0.06, -0.66)),
                         q.z, 0.01) - 0.015;
    float fin = extrude(sdQuad2(p.yz, float2(-0.46, 0.0), float2(-0.72, 0.30), float2(-0.79, 0.30), float2(-0.73, 0.0)),
                        p.x, 0.01) - 0.015;
    float engine = sdSegment(q, float3(0.36, 0.12, -0.07), float3(0.36, -0.10, -0.07), 0.06);
    return min(min(body, wing), min(min(tail, fin), engine));
}

ORB_FORMA(aereo)
