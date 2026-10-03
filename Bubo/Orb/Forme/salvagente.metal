#include "../OrbShading.h"

// Codice · rilascio: a lifebuoy, a ring with four bands; it floats, bobbing and tipping.
static float salvagente(float3 p, float t) {
    p.y -= 0.05 * sin(t * 1.4);
    p.yz = p.yz * rot(0.25 * sin(t * 1.1));
    float d = sdTorusXY(p, 0.62, 0.24);
    for (int i = 0; i < 4; i++) {
        float a = M_PI_F * 0.25 + float(i) * M_PI_F * 0.5;
        float3 q = p - float3(0.62 * cos(a), 0.62 * sin(a), 0);
        q.xy = q.xy * rot(-a);
        d = min(d, sdCylinder(q, 0.27, 0.06));
    }
    return d;
}

ORB_FORMA(salvagente)
