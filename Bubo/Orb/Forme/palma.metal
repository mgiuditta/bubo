#include "../OrbShading.h"

// Viaggi · isole: a palm tree, a bent trunk and five drooping fronds that sway.
static float palma(float3 p, float t) {
    const float2 crown = float2(0.0, 0.35);
    const float angles[5] = { -1.75, -1.0, -0.2, 0.6, 1.35 };
    float d = sdRoundCone(p, float3(-0.25, -0.85, 0), float3(-0.10, -0.20, 0), 0.10, 0.08);
    d = min(d, sdRoundCone(p, float3(-0.10, -0.20, 0), float3(crown, 0), 0.08, 0.06));
    d = min(d, length(p - float3(-0.07, 0.27, 0)) - 0.07);
    d = min(d, length(p - float3(0.07, 0.27, 0)) - 0.07);
    for (int i = 0; i < 5; i++) {
        float a = angles[i] + 0.08 * sin(t * 1.3) * (i % 2 == 0 ? 1.0 : -1.0);
        float2 dir = float2(sin(a), cos(a));
        float2 mid = crown + 0.5 * dir;
        float2 tip = mid + 0.4 * float2(dir.x * 0.8, dir.y * 0.3 - 0.75);
        d = min(d, sdRoundCone(p, float3(crown, 0), float3(mid, 0), 0.06, 0.05));
        d = min(d, sdRoundCone(p, float3(mid, 0), float3(tip, 0), 0.05, 0.015));
    }
    return d;
}

ORB_FORMA(palma)
