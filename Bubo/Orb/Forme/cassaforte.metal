#include "../OrbShading.h"

// Finanza: a safe with a round dial and a spoked handle; the handle turns.
static float cassaforte(float3 p, float t) {
    float body = sdRoundBox(p - float3(0, 0.05, 0), float3(0.72, 0.62, 0.32), 0.08);
    float3 q = float3(abs(p.x), p.y, p.z);
    float feet = sdRoundBox(q - float3(0.50, -0.70, 0), float3(0.12, 0.07, 0.15), 0.02);
    float hinges = sdSegment(q, float3(0.74, 0.38, 0.10), float3(0.74, 0.30, 0.10), 0.07);
    float dial = sdTorusXY(p - float3(0.05, 0.05, 0.33), 0.30, 0.05);
    float hub = length(p - float3(0.05, 0.05, 0.33)) - 0.11;
    float d = min(min(body, feet), min(dial, hub));
    for (int i = 0; i < 4; i++) {
        float ang = t * 0.9 + 1.5707963 * float(i);
        float3 tip = float3(0.05 + 0.40 * cos(ang), 0.05 + 0.40 * sin(ang), 0.33);
        d = min(d, sdSegment(p, float3(0.05, 0.05, 0.33), tip, 0.04));
    }
    return min(d, hinges);
}

ORB_FORMA(cassaforte)
