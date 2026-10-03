#include "../OrbShading.h"

// Chat · riscaldamento e clima in casa: a radiator with six upright elements, two pipes across and a valve.
static float termosifone(float3 p, float) {
    float d = 9.0;
    for (int i = 0; i < 6; i++) {
        float x = -0.6 + 0.24 * float(i);
        d = min(d, sdRoundBox2(p.xy - float2(x, -0.05), float2(0.075, 0.5), 0.07));
    }
    d = min(d, min(udSegment2(p.xy, float2(-0.7, 0.32), float2(0.78, 0.32)) - 0.055, udSegment2(p.xy, float2(-0.7, -0.42), float2(0.78, -0.42)) - 0.055));
    float valve = length(p.xy - float2(0.9, -0.42)) - 0.09;
    float feet = min(udSegment2(p.xy, float2(-0.55, -0.62), float2(-0.55, -0.82)) - 0.05, udSegment2(p.xy, float2(0.55, -0.62), float2(0.55, -0.82)) - 0.05);
    return extrude(min(d, min(valve, feet)), p.z, 0.1) - 0.03;
}

ORB_FORMA(termosifone)
