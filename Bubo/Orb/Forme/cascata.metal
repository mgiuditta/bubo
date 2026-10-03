#include "../OrbShading.h"

// Viaggi: a waterfall, a cliff on the left with a column of water falling into a pool; drops fall beside it
// and the splash bobs.
static float cascata(float3 p, float t) {
    float cliff = sdRoundBox(p - float3(-0.55, 0, 0), float3(0.4, 0.65, 0.35), 0.1);
    float water = sdRoundBox(p - float3(0, 0.05, 0), float3(0.15, 0.62, 0.2), 0.06);
    float pool = sdRoundBox(p - float3(0.1, -0.72, 0), float3(0.75, 0.1, 0.35), 0.08);
    float splash = length(p - float3(0, -0.55 + 0.05 * sin(t * 3.0), 0.1)) - 0.14;
    float d = min(min(cliff, water), min(pool, splash));
    for (int k = 0; k < 3; k++) {
        float y = 0.6 - fract(t * 0.5 + float(k) * 0.33 + 0.3) * 1.2;
        d = min(d, length(p - float3(0.32 + 0.04 * float(k), y, 0)) - 0.05);
    }
    return d;
}

ORB_FORMA(cascata)
