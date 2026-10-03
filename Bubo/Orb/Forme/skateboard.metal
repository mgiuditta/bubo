#include "../OrbShading.h"

// Salute · skateboard: a skateboard in profile, kicked tails at both ends, two trucks and four wheels, tipped up a little.
static float skateboard(float3 p, float) {
    p.xy = p.xy * rot(0.2);
    p.y += 0.2;
    float deck = 9.0;
    const float2 d[4] = { float2(-0.88, 0.0), float2(-0.62, -0.14), float2(0.62, -0.14), float2(0.88, 0.0) };
    for (int i = 0; i < 3; i++) deck = min(deck, udSegment2(p.xy, d[i], d[i + 1]) - 0.065);
    float3 m = float3(abs(p.x), p.y, p.z);
    float truck = sdRoundBox(m - float3(0.48, -0.27, 0), float3(0.07, 0.06, 0.16), 0.02);
    float wheel = sdSegment(m, float3(0.48, -0.4, -0.2), float3(0.48, -0.4, 0.2), 0.13);
    return min(extrude(deck, p.z, 0.18) - 0.03, min(truck, wheel));
}

ORB_FORMA(skateboard)
