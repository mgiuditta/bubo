#include "../OrbShading.h"

// Codice · verifica: a paper scroll rolled up at the top and hanging down, with lines of text; it unrolls a little and rolls back.
static float rotolo(float3 p, float t) {
    float u = 0.5 - 0.5 * cos(t * 0.9);
    float top = 0.6, bottom = -0.65 - 0.2 * u;
    float roll = sdCylinder((p - float3(0, top, 0)).yxz, 0.2 - 0.03 * u, 0.5);
    float sheet = sdRoundBox(p - float3(0, (top + bottom) * 0.5, 0), float3(0.42, (top - bottom) * 0.5, 0.025), 0.01);
    float curl = sdCylinder((p - float3(0, bottom, 0)).yxz, 0.09, 0.44);
    float d = min(roll, min(sheet, curl));
    for (int i = 0; i < 3; i++) {
        float y = 0.25 - 0.3 * float(i);
        float half_ = 0.28 - 0.08 * float(i);
        d = min(d, sdSegment(p, float3(-half_, y, 0.04), float3(half_, y, 0.04), 0.022));
    }
    return d;
}

ORB_FORMA(rotolo)
