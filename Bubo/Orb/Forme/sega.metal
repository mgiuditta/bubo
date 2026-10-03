#include "../OrbShading.h"

// Codice · scrittura: a hand saw, the blade toothed on its lower edge and the handle a closed loop, sawing back and forth.
static float sega(float3 p, float t) {
    p.x -= 0.12 * sin(t * 3.0) + 0.04;
    float2 q = p.xy - float2(0, 0.05);
    float blade = sdQuad2(q, float2(-0.25, 0.20), float2(0.86, 0.12), float2(0.86, -0.10), float2(-0.25, -0.10));
    for (int i = 0; i < 8; i++) {
        float x = -0.20 + 0.105 * float(i);
        blade = min(blade, sdQuad2(q, float2(x, -0.10), float2(x + 0.105, -0.10), float2(x + 0.075, -0.20), float2(x + 0.03, -0.20)));
    }
    float d = extrude(blade, p.z, 0.025) - 0.02;
    float grip = sdTorusXY(p - float3(-0.50, 0.04, 0), 0.20, 0.06);
    float neck = sdSegment(p, float3(-0.34, 0.12, 0), float3(-0.22, 0.10, 0), 0.07);
    return min(d, min(grip, neck));
}

ORB_FORMA(sega)
