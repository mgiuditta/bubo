#include "../OrbShading.h"

// Meteo · tempeste violente: a funnel of six stacked discs, wide at the top; each one circles the axis at its own phase.
static float tornado(float3 p, float t) {
    float d = 9.0;
    for (int i = 0; i < 6; i++) {
        float k = float(i);
        float2 off = 0.1 * float2(sin(t * 2.2 + k * 1.1), cos(t * 2.2 + k * 1.1));
        float3 c = float3(off.x, 0.8 - 0.3 * k, off.y);
        d = min(d, sdCylinder(p - c, 0.78 - 0.12 * k, 0.17));
    }
    return d;
}

ORB_FORMA(tornado)
