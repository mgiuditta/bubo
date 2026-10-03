#include "../OrbShading.h"

// Codice · infrastruttura: three discs stacked on a central column, a status light on each.
static float database(float3 p, float) {
    float d = sdSegment(p, float3(0, -0.5, 0), float3(0, 0.5, 0), 0.13);
    for (int i = 0; i < 3; i++) {
        float y = 0.45 * float(i - 1);
        d = min(d, sdCylinder(p - float3(0, y, 0), 0.57, 0.12) - 0.03);
        d = min(d, length(p - float3(0.36, y, 0.45)) - 0.045);
    }
    return d;
}

ORB_FORMA(database)
