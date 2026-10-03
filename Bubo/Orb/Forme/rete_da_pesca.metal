#include "../OrbShading.h"

// Ricerca: a landing net, a round hoop with a mesh of chords inside it and a long handle down to the left.
static float rete_da_pesca(float3 p, float) {
    p /= 0.9;
    const float2 c = float2(0.25, 0.25);
    const float R = 0.5;
    float d = sdTorusXY(p - float3(c, 0), R, 0.05);
    for (int i = -1; i <= 1; i++) {
        float o = 0.25 * float(i);
        float h = sqrt(R * R - o * o);
        d = min(d, sdSegment(p, float3(c.x + o, c.y - h, 0), float3(c.x + o, c.y + h, 0), 0.022));
        d = min(d, sdSegment(p, float3(c.x - h, c.y + o, 0), float3(c.x + h, c.y + o, 0), 0.022));
    }
    d = min(d, sdSegment(p, float3(-0.1035, -0.1035, 0), float3(-0.85, -0.85, 0), 0.06));
    return d * 0.9;
}

ORB_FORMA(rete_da_pesca)
