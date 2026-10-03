#include "../OrbShading.h"

// Musica: a sound wave drawn as nine bars of different heights, side by side; the peaks rise and fall.
static float onda_sonora(float3 p, float t) {
    const float base[9] = { 0.18, 0.38, 0.62, 0.34, 0.70, 0.46, 0.66, 0.30, 0.16 };
    float d = 9.0;
    for (int i = 0; i < 9; i++) {
        float x = -0.84 + 0.21 * float(i);
        float h = base[i] * (0.8 + 0.2 * sin(t * 2.0 + float(i) * 1.7));
        d = min(d, sdSegment(p, float3(x, -h, 0), float3(x, h, 0), 0.08));
    }
    return d;
}

ORB_FORMA(onda_sonora)
