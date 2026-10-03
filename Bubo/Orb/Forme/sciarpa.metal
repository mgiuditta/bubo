#include "../OrbShading.h"

// One hanging end of the scarf, swung by `swing` radians around `pivot`: a flap with three fringes.
static float sciarpaTail(float3 p, float2 pivot, float swing) {
    float3 q = p;
    q.xy = (p.xy - pivot) * rot(swing);
    float d = sdRoundBox(q - float3(0, -0.32, 0), float3(0.09, 0.32, 0.05), 0.03);
    for (int i = -1; i <= 1; i++) {
        d = min(d, sdSegment(q, float3(0.05 * float(i), -0.64, 0), float3(0.05 * float(i), -0.78, 0), 0.022));
    }
    return d;
}

// Meteo: a scarf wound in a loose ring with two fringed ends hanging from it; the ends sway.
static float sciarpa(float3 p, float t) {
    float d = sdTorusXY(p - float3(0, 0.3, 0), 0.45, 0.16);
    float s1 = 0.15 * sin(t * 2.0);
    float s2 = 0.15 * (sin(t * 2.0 + 1.3) - sin(1.3));
    d = min(d, sciarpaTail(p, float2(0.12, -0.2), s1));
    return min(d, sciarpaTail(p, float2(0.36, -0.02), s2));
}

ORB_FORMA(sciarpa)
