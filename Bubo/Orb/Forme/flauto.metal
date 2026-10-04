#include "../OrbShading.h"

// Musica · fiati: a transverse flute set on the diagonal, a thin tube with the embouchure and a row of keys.
static float flauto(float3 p, float) {
    p.xy = p.xy * rot(-0.5);
    float d = sdSegment(p, float3(-0.95, 0, 0), float3(0.95, 0, 0), 0.065);
    d = min(d, length(p - float3(-0.95, 0, 0)) - 0.09);
    d = min(d, length(p - float3(0.95, 0, 0)) - 0.09);
    d = min(d, length(p - float3(-0.70, 0.09, 0)) - 0.06);
    for (int i = 0; i < 4; i++) d = min(d, length(p - float3(-0.2 + 0.25 * float(i), 0.09, 0)) - 0.055);
    return d;
}

ORB_FORMA(flauto)
