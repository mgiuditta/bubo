#include "../OrbShading.h"

// Codice · rilascio: a rosette, a ring of twelve scallops around a round centre, and two ribbons hanging behind it.
static float coccarda(float3 p, float) {
    float2 c = p.xy - float2(0, 0.25);
    float d2 = length(c) - 0.3;
    for (int i = 0; i < 12; i++) {
        float a = float(i) * 0.5236 + 0.2;
        d2 = min(d2, length(c - 0.38 * float2(cos(a), sin(a))) - 0.13);
    }
    float rosette = extrude(d2, p.z, 0.06);
    float2 q = float2(abs(p.x), p.y);
    float ribbon = extrude(sdQuad2(q, float2(0.28, -0.1), float2(0.02, -0.1), float2(0.12, -0.85), float2(0.42, -0.85)), p.z + 0.05, 0.04);
    return min(rosette, ribbon);
}

ORB_FORMA(coccarda)
