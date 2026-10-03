#include "../OrbShading.h"

// Codice · verifica: a rubber duck in profile, beak to the right, bobbing and tilting as if afloat.
static float papera(float3 p, float t) {
    p.xy = p.xy * rot(-0.12 * sin(t * 1.6));
    p.y -= 0.04 * sin(t * 2.2 + 1.0) - 0.05;
    float body = sdRoundCone(p, float3(-0.22, -0.30, 0), float3(0.26, -0.26, 0), 0.38, 0.30);
    float tail = sdRoundCone(p, float3(-0.50, -0.15, 0), float3(-0.74, 0.12, 0), 0.14, 0.03);
    float neck = sdSegment(p, float3(0.26, -0.10, 0), float3(0.30, 0.28, 0), 0.20);
    float head = length(p - float3(0.30, 0.30, 0)) - 0.27;
    float beak = sdRoundCone(p, float3(0.52, 0.27, 0), float3(0.80, 0.24, 0), 0.10, 0.06);
    float eye = length(p - float3(0.40, 0.40, 0.22)) - 0.05;
    return min(min(min(body, tail), min(neck, head)), min(beak, eye));
}

ORB_FORMA(papera)
