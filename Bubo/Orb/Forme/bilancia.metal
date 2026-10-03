#include "../OrbShading.h"

// Chat · confronto: a two-pan scale; the beam rocks gently and the pans hang from its ends.
static float bilancia(float3 p, float t) {
    const float2 pivot = float2(0, 0.6);
    float a = 0.12 * sin(t * 1.2);
    float2 arm = float2(cos(a), sin(a)) * 0.65;
    float2 right = pivot + arm, left = pivot - arm;
    float post = sdSegment(p, float3(0, -0.72, 0), float3(0, 0.6, 0), 0.05);
    float base = sdRoundBox(p - float3(0, -0.76, 0), float3(0.36, 0.05, 0.12), 0.04);
    float beam = sdSegment(p, float3(left, 0), float3(right, 0), 0.05);
    float top = length(p - float3(0, 0.68, 0)) - 0.08;
    float d = min(min(post, base), min(beam, top));
    for (int s = 0; s < 2; s++) {
        float2 e = s == 0 ? left : right;
        float2 pan = e - float2(0, 0.5);
        d = min(d, sdSegment(p, float3(e, 0), float3(pan + float2(-0.22, 0), 0), 0.02));
        d = min(d, sdSegment(p, float3(e, 0), float3(pan + float2(0.22, 0), 0), 0.02));
        d = min(d, sdCylinder(p - float3(pan, 0), 0.20, 0.02) - 0.02);
    }
    return d;
}

ORB_FORMA(bilancia)
