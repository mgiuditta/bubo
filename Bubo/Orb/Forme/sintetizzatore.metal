#include "../OrbShading.h"

// Musica · elettronica: a short synthesizer, a row of knobs above a keyboard; the first knob turns.
static float sintetizzatore(float3 p, float t) {
    float panel = sdRoundBox(p - float3(0, 0.06, 0), float3(0.88, 0.28, 0.12), 0.05);
    float d = panel;
    for (int i = 0; i < 5; i++) {
        float x = -0.6 + 0.3 * float(i);
        d = min(d, sdCylinder(float3(p.x - x, p.z - 0.12, p.y - 0.42), 0.09, 0.07));
        float a = i == 0 ? 2.0 * t + 0.8 : 0.8 + 0.9 * float(i);
        float2 tick = float2(sin(a), cos(a)) * 0.075;
        d = min(d, sdSegment(p, float3(x, 0.42, 0.2), float3(float2(x, 0.42) + tick, 0.2), 0.02));
    }
    for (int i = 0; i < 8; i++) {
        float x = -0.7 + 0.2 * float(i);
        d = min(d, sdRoundBox(p - float3(x, -0.38, 0), float3(0.075, 0.3, 0.12), 0.012));
    }
    for (int i = 0; i < 7; i++) {
        if (i == 2 || i == 6) continue;
        float x = -0.6 + 0.2 * float(i);
        d = min(d, sdRoundBox(p - float3(x, -0.2, 0.1), float3(0.05, 0.18, 0.12), 0.012));
    }
    return d;
}

ORB_FORMA(sintetizzatore)
