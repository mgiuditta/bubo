#include "../OrbShading.h"

// Ricerca · filtrare: a round sieve with a mesh and a handle; it shakes from side to side.
static float setaccio(float3 p, float t) {
    float3 q = p - float3(0.15 * sin(t * 4.0), 0, 0);
    float3 c = q - float3(-0.2, 0, 0);
    float d = sdTorusXY(c, 0.6, 0.06);
    for (int i = 0; i < 3; i++) {
        float o = -0.3 + 0.3 * float(i);
        float h = sqrt(max(0.36 - o * o, 0.0));
        d = min(d, sdSegment(c, float3(o, -h, 0), float3(o, h, 0), 0.025));
        d = min(d, sdSegment(c, float3(-h, o, 0), float3(h, o, 0), 0.025));
    }
    float handle = sdSegment(q, float3(0.4, 0, 0), float3(0.9, 0, 0), 0.06);
    float end = length(q - float3(0.95, 0, 0)) - 0.09;
    return min(d, min(handle, end));
}

ORB_FORMA(setaccio)
