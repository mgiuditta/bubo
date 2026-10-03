#include "../OrbShading.h"

// Chat · natura: a penguin standing, flippers out, waddling from side to side on its feet.
static float pinguino(float3 p, float t) {
    float3 pivot = float3(0, -0.78, 0);
    p -= pivot;
    p.xy = p.xy * rot(0.1 * sin(t * 2.2));
    p += pivot;
    float body = sdRoundCone(p, float3(0, -0.4, 0), float3(0, 0.3, 0), 0.34, 0.24);
    float head = length(p - float3(0, 0.52, 0)) - 0.2;
    float beak = sdRoundCone(p, float3(0.12, 0.52, 0), float3(0.36, 0.46, 0), 0.06, 0.02);
    float3 q = float3(abs(p.x), p.y, p.z);
    float flipper = sdSegment(q, float3(0.3, 0.18, 0), float3(0.5, -0.2, 0), 0.06);
    float feet = sdRoundBox(q - float3(0.15, -0.78, 0.08), float3(0.12, 0.03, 0.1), 0.03);
    return min(min(body, head), min(min(beak, flipper), feet));
}

ORB_FORMA(pinguino)
