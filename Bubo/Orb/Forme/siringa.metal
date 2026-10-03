#include "../OrbShading.h"

// Salute · corpo: a syringe on the diagonal: barrel, flange, plunger and needle.
static float siringa(float3 p, float) {
    float3 q = p;
    q.xy = p.xy * rot(-0.6);
    float barrel = sdRoundBox(q, float3(0.45, 0.14, 0.14), 0.06);
    float flange = sdRoundBox(q - float3(-0.45, 0, 0), float3(0.04, 0.30, 0.10), 0.02);
    float rod = sdSegment(q, float3(-0.50, 0, 0), float3(-0.80, 0, 0), 0.04);
    float thumb = sdRoundBox(q - float3(-0.84, 0, 0), float3(0.04, 0.20, 0.08), 0.02);
    float hub = sdRoundCone(q, float3(0.45, 0, 0), float3(0.58, 0, 0), 0.10, 0.04);
    float needle = sdSegment(q, float3(0.58, 0, 0), float3(0.95, 0, 0), 0.03);
    float ticks = 9.0;
    for (int i = 0; i < 4; i++) {
        float x = -0.25 + 0.15 * float(i);
        ticks = min(ticks, sdSegment(q, float3(x, 0.0, 0.14), float3(x, 0.08, 0.14), 0.025));
    }
    return min(min(min(barrel, flange), min(rod, thumb)), min(min(hub, needle), ticks));
}

ORB_FORMA(siringa)
