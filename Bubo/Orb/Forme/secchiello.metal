#include "../OrbShading.h"

// Agente · sandbox: a beach bucket with an arched handle and a little spade leaning against it.
static float secchiello(float3 p, float) {
    p.x += 0.1;
    float3 b = p - float3(-0.2, -0.1, 0);
    float bucket = sdCappedCone(b, 0.4, 0.3, 0.4);
    float rim = sdCylinder(b - float3(0, 0.4, 0), 0.43, 0.04);
    const float2 h[5] = { float2(-0.62, 0.3), float2(-0.55, 0.6), float2(-0.2, 0.74), float2(0.15, 0.6), float2(0.22, 0.3) };
    float handle = 9.0;
    for (int i = 0; i < 4; i++) handle = min(handle, sdSegment(p, float3(h[i], 0), float3(h[i + 1], 0), 0.04));
    float2 blade = (p.xy - float2(0.7, -0.62)) * rot(0.25);
    float spade = min(udSegment2(p.xy, float2(0.5, 0.2), float2(0.66, -0.4)) - 0.05, sdRoundBox2(blade, float2(0.12, 0.17), 0.04));
    return min(min(bucket, rim), min(handle, extrude(spade, p.z, 0.04) - 0.02));
}

ORB_FORMA(secchiello)
