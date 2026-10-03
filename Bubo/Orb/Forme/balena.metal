#include "../OrbShading.h"

// Chat · balene e delfini: a whale in profile with its tail raised, blowing a spout that rises and falls.
static float balena(float3 p, float t) {
    p.y += 0.12;
    p.x += 0.05;
    float2 q = p.xy;
    float body = udSegment2(q, float2(-0.3, -0.12), float2(0.4, -0.18)) - 0.36;
    float stalk = udSegment2(q, float2(-0.5, -0.05), float2(-0.8, 0.28)) - 0.12;
    float fluke = min(udSegment2(q, float2(-0.8, 0.28), float2(-1.0, 0.55)), udSegment2(q, float2(-0.8, 0.28), float2(-0.58, 0.55))) - 0.07;
    float flesh = extrude(min(body, min(stalk, fluke)), p.z, 0.1) - 0.04;
    float eye = length(p - float3(0.52, -0.05, 0.14)) - 0.04;
    float rise = 0.15 + 0.3 * (0.5 + 0.5 * sin(t * 2.0));
    float3 base = float3(0.3, 0.22, 0);
    float3 top = base + float3(0, rise, 0);
    float spout = sdSegment(p, base, top, 0.045);
    spout = min(spout, min(sdSegment(p, top, top + float3(0.16, -0.1, 0), 0.04), sdSegment(p, top, top + float3(-0.16, -0.1, 0), 0.04)));
    return min(min(flesh, eye), spout);
}

ORB_FORMA(balena)
