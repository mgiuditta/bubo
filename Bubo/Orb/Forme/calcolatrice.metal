#include "../OrbShading.h"

// Finanza: a calculator with its display and three columns of keys.
static float calcolatrice(float3 p, float) {
    float d = sdRoundBox(p, float3(0.50, 0.75, 0.08), 0.06);
    d = min(d, sdRoundBox(p - float3(0, 0.50, 0.08), float3(0.36, 0.14, 0.03), 0.02));
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 4; j++) {
            d = min(d, sdRoundBox(p - float3(-0.27 + 0.27 * float(i), 0.15 - 0.25 * float(j), 0.08), float3(0.10, 0.08, 0.03), 0.02));
        }
    }
    return d;
}

ORB_FORMA(calcolatrice)
