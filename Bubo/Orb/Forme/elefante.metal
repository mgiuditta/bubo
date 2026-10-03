#include "../OrbShading.h"

// Agente · memoria: an elephant in profile facing right, trunk raised and swaying.
static float elefante(float3 p, float t) {
    p.x += 0.06;
    float d = length(p - float3(-0.20, -0.05, 0)) - 0.42;
    d = min(d, length(p - float3(0.38, 0.10, 0)) - 0.28);
    d = min(d, length(p - float3(0.10, 0.28, 0.05)) - 0.22);
    float2 tip = float2(0.80 + 0.08 * sin(t * 1.4), 0.55);
    d = min(d, sdRoundCone(p, float3(0.45, 0.10, 0), float3(tip, 0), 0.14, 0.06));
    for (int i = 0; i < 4; i++) {
        float x = -0.5 + 0.23 * float(i);
        d = min(d, sdSegment(p, float3(x, -0.35, 0), float3(x, -0.85, 0), 0.085));
    }
    return min(d, sdSegment(p, float3(-0.60, 0.05, 0), float3(-0.74, -0.30, 0), 0.03));
}

ORB_FORMA(elefante)
