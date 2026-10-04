#include "../OrbShading.h"

// Agente: a to-do list: three dots on the left, each with its line.
static float elenco(float3 p, float) {
    float d = 9.0;
    for (int i = 0; i < 3; i++) {
        float y = 0.46 - 0.46 * float(i);
        d = min(d, length(p - float3(-0.55, y, 0)) - 0.13);
        d = min(d, sdSegment(p, float3(-0.2, y, 0), float3(0.62, y, 0), 0.085));
    }
    return d;
}

ORB_FORMA(elenco)
