#include "../OrbShading.h"

// Salute · igiene: an oval bar of soap with three bubbles that rise, swell and vanish one after the other.
static float saponetta(float3 p, float t) {
    float bar = sdRoundBox(p - float3(0, -0.5, 0), float3(0.55, 0.17, 0.3), 0.17);
    float d = bar;
    const float3 bubbles[3] = { float3(-0.3, 0, 0), float3(0.12, 0, 0), float3(0.42, 0, 0) };
    for (int i = 0; i < 3; i++) {
        float ph = fract(t / 3.2 + 0.3 + 0.27 * float(i));
        float life = smoothstep(0.0, 0.12, ph) * (1.0 - smoothstep(0.82, 1.0, ph));
        float3 c = float3(bubbles[i].x + 0.05 * sin(t + float(i) * 2.0), -0.22 + 1.0 * ph, 0.0);
        d = min(d, length(p - c) - (0.11 + 0.035 * float(i)) * life);
    }
    return d;
}

ORB_FORMA(saponetta)
