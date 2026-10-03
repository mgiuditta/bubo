#include "../OrbShading.h"

// Chat · idraulica: a tap with a cross handle and a bending spout; a drop swells, falls and starts again.
static float rubinetto(float3 p, float t) {
    p.y -= 0.05;
    float2 q = p.xy;
    float post = udSegment2(q, float2(-0.35, -0.5), float2(-0.35, 0.12)) - 0.1;
    float spout = min(udSegment2(q, float2(-0.35, 0.12), float2(0.3, 0.12)) - 0.13, udSegment2(q, float2(0.3, 0.12), float2(0.3, -0.08)) - 0.13);
    float stem = udSegment2(q, float2(-0.35, 0.12), float2(-0.35, 0.42)) - 0.06;
    float cross = udSegment2(q, float2(-0.57, 0.46), float2(-0.13, 0.46)) - 0.07;
    float base = sdRoundBox2(q - float2(-0.35, -0.55), float2(0.24, 0.07), 0.04);
    float tap = extrude(min(min(post, spout), min(min(stem, cross), base)), p.z, 0.1) - 0.04;
    float ph = fract(t / 1.6 + 0.5);
    float grow = smoothstep(0.0, 0.15, ph);
    float fall = ph * ph;
    float3 top = float3(0.3, -0.3 - 0.6 * fall + 0.16 * (1.0 - grow), 0);
    float drop = sdRoundCone(p, top, top + float3(0, 0.2 * grow + 0.02, 0), 0.1 * grow, 0.012);
    return min(tap, drop);
}

ORB_FORMA(rubinetto)
