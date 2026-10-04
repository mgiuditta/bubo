#include "../OrbShading.h"

// Codice · refactor: a wall of six staggered bricks in three courses; one brick slides out and back into place.
static float mattoni(float3 p, float t) {
    const float2 bricks[6] = { float2(-0.18, -0.40), float2(0.54, -0.40), float2(-0.54, 0.0),
                               float2(0.18, 0.0), float2(-0.18, 0.40), float2(0.54, 0.40) };
    float ph = fract(t / 5.0 + 0.3);
    float slide = 0.95 * (smoothstep(0.80, 0.95, ph) + 1.0 - smoothstep(0.0, 0.2, ph));
    float d = 9.0;
    for (int i = 0; i < 6; i++) {
        float2 c = bricks[i];
        if (i == 5) c.x += slide;
        d = min(d, sdRoundBox(p - float3(c, 0), float3(0.32, 0.16, 0.18), 0.04));
    }
    return d;
}

ORB_FORMA(mattoni)
