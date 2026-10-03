#include "../OrbShading.h"

// Codice · hardware: a square chip with four pins on its sides and three on top and bottom, and a dot marking its corner.
static float microchip(float3 p, float) {
    float d = sdRoundBox2(p.xy, float2(0.45), 0.06);
    for (int i = 0; i < 4; i++) {
        float s = -0.3 + 0.2 * float(i);
        d = min(d, sdRoundBox2(p.xy - float2(0.52, s), float2(0.13, 0.03), 0.01));
        d = min(d, sdRoundBox2(p.xy - float2(-0.52, s), float2(0.13, 0.03), 0.01));
    }
    for (int i = 0; i < 3; i++) {
        float s = -0.25 + 0.25 * float(i);
        d = min(d, sdRoundBox2(p.xy - float2(s, 0.52), float2(0.03, 0.13), 0.01));
        d = min(d, sdRoundBox2(p.xy - float2(s, -0.52), float2(0.03, 0.13), 0.01));
    }
    return min(extrude(d, p.z, 0.06) - 0.03, length(p - float3(-0.28, 0.28, 0.10)) - 0.06);
}

ORB_FORMA(microchip)
