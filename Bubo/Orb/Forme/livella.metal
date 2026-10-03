#include "../OrbShading.h"

// Codice · stile del codice: a spirit level, a bar with a vial in the middle; the bubble drifts and comes back.
static float livella(float3 p, float t) {
    float bar = sdRoundBox(p, float3(0.85, 0.2, 0.1), 0.06);
    float rings = min(sdTorusXY(p - float3(-0.55, 0, 0.12), 0.1, 0.03), sdTorusXY(p - float3(0.55, 0, 0.12), 0.1, 0.03));
    float vial = sdRoundBox(p - float3(0, 0, 0.12), float3(0.28, 0.07, 0.02), 0.03);
    float bubble = length(p - float3(0.14 * sin(t * 1.8), 0, 0.17)) - 0.06;
    return min(min(bar, rings), min(vial, bubble));
}

ORB_FORMA(livella)
