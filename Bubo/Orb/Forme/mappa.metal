#include "../OrbShading.h"

// Viaggi · itinerario: a map folded in three panels, zigzag, each with a dotted path and a pin.
static float mappa(float3 p, float) {
    float d = 9.0;
    for (int i = 0; i < 3; i++) {
        float side = (i % 2 == 0) ? 1.0 : -1.0;
        float3 q = p - float3(0.527 * float(i - 1), 0, 0);
        q.xz = q.xz * rot(0.5 * side);
        d = min(d, sdRoundBox(q, float3(0.30, 0.75, 0.02), 0.02));
        d = min(d, sdSegment(q, float3(-0.12, -0.45, 0.04), float3(0.12, -0.10, 0.04), 0.025));
        d = min(d, length(q - float3(0, 0.35, 0.05)) - 0.055);
    }
    return d;
}

ORB_FORMA(mappa)
