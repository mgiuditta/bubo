#include "../OrbShading.h"

// Finanza: a bar chart of four rising bars on a baseline; the bars swell in turn.
static float grafico_barre(float3 p, float t) {
    float d = sdSegment(p, float3(-0.85, -0.84, 0), float3(0.85, -0.84, 0), 0.03);
    const float heights[4] = { 0.45, 0.75, 1.10, 1.50 };
    for (int i = 0; i < 4; i++) {
        float h = heights[i] * (0.85 + 0.15 * sin(t * 2.0 - float(i) * 0.9));
        d = min(d, sdRoundBox(p - float3(-0.6 + 0.4 * float(i), -0.8 + h * 0.5, 0), float3(0.13, h * 0.5, 0.10), 0.03));
    }
    return d;
}

ORB_FORMA(grafico_barre)
