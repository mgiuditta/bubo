#include "../OrbShading.h"

// Tempo · durate: a stopwatch, a round body with a bezel, ticks, a button on top and one at the side; its hand turns.
static float cronometro(float3 p, float t) {
    float3 q = p + float3(0, 0.18, 0);
    float body = extrude(length(q.xy) - 0.43, q.z, 0.09) - 0.12;
    float bezel = sdTorusXY(q - float3(0, 0, 0.14), 0.50, 0.04);
    float stem = sdCylinder(q - float3(0, 0.68, 0), 0.10, 0.13);
    float cap = sdCylinder(q - float3(0, 0.88, 0), 0.17, 0.05) - 0.02;
    float side = sdSegment(q, float3(0.40, 0.45, 0), float3(0.55, 0.60, 0), 0.07);
    float d = min(min(body, bezel), min(min(stem, cap), side));
    for (int i = 0; i < 12; i++) {
        float a = 0.5235988 * float(i);
        d = min(d, length(q - float3(0.38 * sin(a), 0.38 * cos(a), 0.15)) - (i % 3 == 0 ? 0.04 : 0.025));
    }
    float a = t * 1.2;
    d = min(d, sdSegment(q, float3(0, 0, 0.17), float3(sin(a), cos(a), 0) * 0.34 + float3(0, 0, 0.17), 0.03));
    return d;
}

ORB_FORMA(cronometro)
