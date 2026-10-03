#include "../OrbShading.h"

// Codice: a rocket with a nose cone, a porthole, two fins and a flame that pulses underneath.
static float razzo(float3 p, float t) {
    p.y -= 0.10;
    float3 q = float3(abs(p.x), p.y, p.z);
    float body = sdCylinder(p - float3(0, -0.25, 0), 0.30, 0.45);
    float nose = sdRoundCone(p, float3(0, 0.20, 0), float3(0, 0.88, 0), 0.30, 0.05);
    float window = sdTorusXY(p - float3(0, 0.0, 0.28), 0.10, 0.04);
    float2 a = float2(0.28, -0.12), b = float2(0.62, -0.78), c = float2(0.28, -0.62);
    float fin = extrude(sdQuad2(q.xy, a, b, c, 0.5 * (a + c)), q.z, 0.03) - 0.02;
    float length_ = 0.28 + 0.08 * sin(t * 14.0);
    float flame = sdRoundCone(p, float3(0, -0.78, 0), float3(0, -0.78 - length_, 0), 0.16, 0.03);
    return min(min(body, nose), min(window, min(fin, flame)));
}

ORB_FORMA(razzo)
