#include "../OrbShading.h"

// Musica: a xylophone of six bars, longest to shortest, on two rails, with two mallets; one bounces.
static float xilofono(float3 p, float t) {
    p /= 0.9;
    float d = 9.0;
    for (int i = 0; i < 6; i++) {
        d = min(d, sdRoundBox(p - float3(-0.65 + 0.26 * float(i), -0.1, 0), float3(0.07, 0.5 - 0.06 * float(i), 0.05), 0.03));
    }
    d = min(d, sdSegment(p, float3(-0.82, 0.04, -0.05), float3(0.82, 0.04, -0.05), 0.04));
    d = min(d, sdSegment(p, float3(-0.82, -0.24, -0.05), float3(0.82, -0.24, -0.05), 0.04));
    float bounce = 0.12 * abs(sin(t * 3.0));
    float3 head = float3(0.39, 0.3 + bounce, 0.1);
    d = min(d, min(length(p - head) - 0.1, sdSegment(p, head, float3(0.47, 0.92, 0.1), 0.03)));
    d = min(d, min(length(p - float3(0.65, 0.25, 0.1)) - 0.1, sdSegment(p, float3(0.65, 0.25, 0.1), float3(0.9, 0.8, 0.1), 0.03)));
    return d * 0.9;
}

ORB_FORMA(xilofono)
