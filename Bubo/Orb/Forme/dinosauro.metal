#include "../OrbShading.h"

// Chat: a long-necked dinosaur in profile, a heavy body, a tapering tail and four legs; the neck sways slowly.
static float dinosauro(float3 p, float t) {
    float3 head = float3(0.55 + 0.07 * sin(t * 0.6), 0.55 + 0.06 * cos(t * 0.45), 0);
    float body = sdRoundCone(p, float3(-0.40, -0.20, 0), float3(0.10, -0.15, 0), 0.26, 0.32);
    float tail = sdRoundCone(p, float3(-0.40, -0.20, 0), float3(-0.98, -0.50, 0), 0.22, 0.04);
    float neck = sdRoundCone(p, float3(0.12, -0.02, 0), head, 0.17, 0.09);
    float skull = length(p - head - float3(0.07, -0.02, 0)) - 0.13;
    float d = min(min(body, tail), min(neck, skull));
    for (int i = 0; i < 4; i++) {
        float x = -0.35 + 0.17 * float(i);
        d = min(d, sdSegment(p, float3(x, -0.35, 0), float3(x, -0.75, 0), 0.09));
    }
    return d;
}

ORB_FORMA(dinosauro)
