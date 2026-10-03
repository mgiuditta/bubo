#include "../OrbShading.h"

// Tempo: a disc split in half, a sun on one side and a crescent moon on the other, turning slowly.
static float giorno_notte(float3 p, float t) {
    float3 q = p;
    q.xy = p.xy * rot(-t * 0.35);
    float ring = sdTorusXY(q, 0.75, 0.06);
    float divider = sdSegment(q, float3(0, -0.72, 0), float3(0, 0.72, 0), 0.035);
    float sun = length(q - float3(-0.38, 0, 0)) - 0.17;
    for (int i = 0; i < 8; i++) {
        float2 dir = float2(cos(0.7853982 * float(i)), sin(0.7853982 * float(i)));
        float2 c = float2(-0.38, 0);
        sun = min(sun, sdSegment(q, float3(c + dir * 0.27, 0), float3(c + dir * 0.37, 0), 0.04));
    }
    float2 m = q.xy - float2(0.30, 0);
    float moon = extrude(min(udQuarterArc(m, float2(0), 0.24, float2(1, 1)), udQuarterArc(m, float2(0), 0.24, float2(1, -1))) - 0.03, q.z, 0.01) - 0.03;
    float star = length(q - float3(0.52, 0.42, 0)) - 0.05;
    return min(min(ring, divider), min(min(sun, moon), star));
}

ORB_FORMA(giorno_notte)
