#include "../OrbShading.h"

// Chat · natura: a spiral shell, the whorls growing outward from a small tip.
static float conchiglia(float3 p, float) {
    p.x -= 0.19;
    float d = 9.0;
    for (int i = 0; i < 28; i++) {
        float a = float(i) * (3.0 * M_PI_F / 27.0);
        float c = 0.5 * exp(0.2 * (a - 3.0 * M_PI_F));
        d = min(d, length(p - float3(c * cos(a), c * sin(a), 0)) - 0.5 * c);
    }
    return d;
}

ORB_FORMA(conchiglia)
