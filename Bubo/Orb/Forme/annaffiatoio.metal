#include "../OrbShading.h"

// Distance to the upper half of the circle of radius R around the origin.
static float annaffiatoioArc(float2 q, float R) {
    return q.y >= 0.0 ? abs(length(q) - R) : min(length(q - float2(R, 0)), length(q + float2(R, 0)));
}

// Chat: a watering can with a long spout and a rose, tipping forward now and then as if pouring.
static float annaffiatoio(float3 p, float t) {
    p.xy = p.xy * rot(0.28 * (0.5 - 0.5 * cos(t * 0.8)));
    p.x += 0.23;
    float2 q = p.xy;
    float d = sdRoundBox2(q - float2(-0.1, -0.2), float2(0.40, 0.38), 0.14);
    d = min(d, udSegment2(q, float2(0.25, -0.35), float2(0.78, 0.25)) - 0.07);
    d = min(d, length(q - float2(0.82, 0.30)) - 0.15);
    d = min(d, annaffiatoioArc(q - float2(-0.10, 0.12), 0.36) - 0.045);
    return extrude(d, p.z, 0.06) - 0.03;
}

ORB_FORMA(annaffiatoio)
