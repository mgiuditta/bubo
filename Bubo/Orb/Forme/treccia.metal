#include "../OrbShading.h"

// Codice · scrittura: a braid of three strands weaving in and out, upright.
static float treccia(float3 p, float) {
    float d = 9.0;
    for (int s = 0; s < 3; s++) {
        float ph = float(s) * 2.0943951;
        float3 prev = float3(0.22 * sin(-3.6 + ph), -0.9, 0.13 * cos(-3.6 + ph));
        for (int i = 1; i <= 16; i++) {
            float y = -0.9 + 0.1125 * float(i);
            float a = 4.0 * y + ph;
            float3 next = float3(0.22 * sin(a), y, 0.13 * cos(a));
            d = min(d, sdSegment(p, prev, next, 0.12));
            prev = next;
        }
    }
    return d;
}

ORB_FORMA(treccia)
