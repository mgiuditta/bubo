#include "../OrbShading.h"

// Codice · archivi: a stretch of zip, two tapes with interlocking teeth and the slider going up and down.
static float cerniera(float3 p, float t) {
    float ys = 0.25 * sin(t * 0.7);
    float d = min(udSegment2(p.xy, float2(-0.30, -0.85), float2(-0.30, 0.85)),
                  udSegment2(p.xy, float2(0.30, -0.85), float2(0.30, 0.85))) - 0.035;
    for (int i = 0; i < 8; i++) {
        float y = -0.7 + 0.2 * float(i);
        d = min(d, sdRoundBox2(p.xy - float2(-0.14, y), float2(0.12, 0.07), 0.02));
        d = min(d, sdRoundBox2(p.xy - float2(0.14, y + 0.1), float2(0.12, 0.07), 0.02));
    }
    d = min(d, sdRoundBox2(p.xy - float2(0, ys), float2(0.17, 0.16), 0.05));
    d = min(d, sdRoundBox2(p.xy - float2(0, ys - 0.33), float2(0.07, 0.12), 0.04));
    return extrude(d, p.z, 0.05) - 0.03;
}

ORB_FORMA(cerniera)
