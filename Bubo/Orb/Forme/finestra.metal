#include "../OrbShading.h"

// Codice · scrittura: a window with a thick frame, a cross of bars between four panes and a sill.
static float finestra(float3 p, float) {
    float frame = extrude(abs(sdRoundBox2(p.xy, float2(0.58, 0.66), 0.05)) - 0.07, p.z, 0.07);
    float bars = min(sdRoundBox(p, float3(0.05, 0.64, 0.05), 0.02), sdRoundBox(p, float3(0.57, 0.05, 0.05), 0.02));
    float glass = sdRoundBox(p, float3(0.54, 0.62, 0.02), 0.015);
    float sill = sdRoundBox(p - float3(0, -0.78, 0.1), float3(0.72, 0.05, 0.12), 0.04);
    return min(min(frame, bars), min(glass, sill));
}

ORB_FORMA(finestra)
