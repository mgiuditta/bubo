#include "../OrbShading.h"

// Meteo · nebbia: four wavy lines, one above the other and out of step, drifting sideways at their own pace.
static float nebbia(float3 p, float t) {
    float d = 9.0;
    for (int i = 0; i < 4; i++) {
        float k = float(i);
        float x = p.x - 0.15 * sin(t + k * 1.5);
        float y = 0.5 - 0.33 * k;
        for (int s = 0; s < 5; s++) {
            float x0 = -0.7 + 0.28 * float(s), x1 = x0 + 0.28;
            float y0 = y + (s % 2 == 0 ? -0.06 : 0.06), y1 = y + (s % 2 == 0 ? 0.06 : -0.06);
            d = min(d, udSegment2(float2(x, p.y), float2(x0, y0), float2(x1, y1)));
        }
    }
    return extrude(d - 0.05, p.z, 0.04) - 0.02;
}

ORB_FORMA(nebbia)
