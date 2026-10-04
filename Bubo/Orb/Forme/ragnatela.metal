#include "../OrbShading.h"

// Codice: a round spider web, eight spokes and three rings.
static float ragnatela(float3 p, float) {
    float2 q = p.xy;
    float d = abs(length(q) - 0.30);
    d = min(d, abs(length(q) - 0.56));
    d = min(d, abs(length(q) - 0.82));
    for (int i = 0; i < 8; i++) {
        float a = float(i) * M_PI_F * 0.25;
        d = min(d, udSegment2(q, float2(0), float2(cos(a), sin(a)) * 0.88));
    }
    return extrude(d - 0.03, p.z, 0.015) - 0.02;
}

ORB_FORMA(ragnatela)
