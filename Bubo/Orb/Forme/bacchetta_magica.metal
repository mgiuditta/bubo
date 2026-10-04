#include "../OrbShading.h"

// Creativo · immagini con l'IA: a wand on the diagonal, a star on its tip that pulses and twists.
static float bacchetta_magica(float3 p, float t) {
    float wand = sdSegment(p, float3(-0.65, -0.65, 0), float3(0.35, 0.35, 0), 0.06);
    float bands = min(sdSegment(p, float3(-0.65, -0.65, 0), float3(-0.5, -0.5, 0), 0.08),
                      sdSegment(p, float3(0.2, 0.2, 0), float3(0.3, 0.3, 0), 0.08));
    float s = 1.0 + 0.12 * sin(t * 4.0);
    float3 q = p - float3(0.5, 0.5, 0);
    q.xy = q.xy * rot(0.3 * sin(t * 2.0));
    q /= s;
    float star = (extrude(sdStar5(q.xy, 0.3, 0.45), q.z, 0.06) - 0.02) * s;
    return min(min(wand, bands), star);
}

ORB_FORMA(bacchetta_magica)
