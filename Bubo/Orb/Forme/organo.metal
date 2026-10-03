#include "../OrbShading.h"

// Musica: a pipe organ, seven pipes of rising height on a low case.
static float organo(float3 p, float) {
    float d = sdRoundBox(p - float3(0, -0.6, 0), float3(0.7, 0.1, 0.2), 0.05);
    for (int i = 0; i < 7; i++) {
        float h = 0.35 + 0.15 * float(i);
        d = min(d, sdCylinder(p - float3(0.19 * float(i - 3), -0.5 + 0.5 * h, 0), 0.08, 0.5 * h));
    }
    return d;
}

ORB_FORMA(organo)
