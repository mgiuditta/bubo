#include "../OrbShading.h"

// Codice · approvazione: a rubber stamp over its ink pad; it comes down to the pad and goes back up.
static float timbro(float3 p, float t) {
    float dy = 0.15 * (1.0 + cos(t * 1.8));            // 0.3 up, 0 on the pad
    float pad = sdRoundBox(p - float3(0, -0.75, 0), float3(0.70, 0.07, 0.35), 0.04);
    float3 s = p - float3(0, dy, 0);
    float base = sdRoundBox(s - float3(0, -0.50, 0), float3(0.50, 0.09, 0.30), 0.05);
    float neck = sdSegment(s, float3(0, -0.45, 0), float3(0, 0.20, 0), 0.09);
    float knob = length(s - float3(0, 0.32, 0)) - 0.17;
    return min(min(pad, base), min(neck, knob));
}

ORB_FORMA(timbro)
