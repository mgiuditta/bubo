#include "../OrbShading.h"

// Codice · migrazioni: an arch bridge, a deck with a rail over one arch on two piers.
static float ponte(float3 p, float) {
    const float2 c = float2(0, -0.5);
    float arch = min(udQuarterArc(p.xy, c, 0.7, float2(1, 1)), udQuarterArc(p.xy, c, 0.7, float2(-1, 1))) - 0.08;
    float deck = udSegment2(p.xy, float2(-0.95, 0.25), float2(0.95, 0.25)) - 0.07;
    float rail = udSegment2(p.xy, float2(-0.95, 0.4), float2(0.95, 0.4)) - 0.03;
    float posts = 9.0;
    for (int i = 0; i < 5; i++) {
        float x = -0.9 + 0.45 * float(i);
        posts = min(posts, udSegment2(p.xy, float2(x, 0.25), float2(x, 0.4)) - 0.03);
    }
    float piers = min(udSegment2(float2(abs(p.x), p.y), float2(0.7, -0.5), float2(0.7, -0.9)) - 0.1, 9.0);
    return extrude(min(min(arch, deck), min(min(rail, posts), piers)), p.z, 0.07) - 0.02;
}

ORB_FORMA(ponte)
