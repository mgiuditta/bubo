#include "../OrbShading.h"

// Ricerca: a bookshelf, an open frame with five books of different heights standing on the bottom board.
static float scaffale(float3 p, float) {
    float2 q = p.xy;
    float d = abs(sdRoundBox2(q, float2(0.72, 0.78), 0.04)) - 0.06;
    const float heights[5] = { 1.00, 0.75, 1.20, 0.85, 1.10 };
    for (int i = 0; i < 5; i++) {
        float h = heights[i];
        d = min(d, sdRoundBox2(q - float2(-0.5 + 0.25 * float(i), -0.72 + 0.5 * h), float2(0.085, 0.5 * h), 0.02));
    }
    return extrude(d, p.z, 0.05) - 0.02;
}

ORB_FORMA(scaffale)
