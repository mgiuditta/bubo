#include "../OrbShading.h"

// Codice · infrastruttura: a shipping container with its vertical ribs and corner posts.
static float container(float3 p, float) {
    float d = sdRoundBox(p, float3(0.84, 0.46, 0.28), 0.04);
    for (int i = 0; i < 7; i++) {
        float x = -0.60 + 0.20 * float(i);
        d = min(d, sdRoundBox(p - float3(x, 0, 0.30), float3(0.045, 0.40, 0.05), 0.015));
    }
    float3 q = float3(abs(p.x), abs(p.y), p.z);
    d = min(d, sdRoundBox(q - float3(0.82, 0.44, 0.28), float3(0.07, 0.07, 0.07), 0.02));
    return d;
}

ORB_FORMA(container)
