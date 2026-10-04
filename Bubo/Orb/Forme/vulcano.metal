#include "../OrbShading.h"

// Chat · geologia: a volcano, a wide cone with a flat crater and a thread of smoke rising.
static float vulcano(float3 p, float t) {
    float cone = sdQuad2(p.xy, float2(-0.85, -0.80), float2(0.85, -0.80), float2(0.28, 0.35), float2(-0.28, 0.35));
    float d = extrude(cone, p.z, 0.12) - 0.04;
    for (int i = 0; i < 3; i++) {
        float ph = fract(t * 0.25 + float(i) / 3.0);
        float2 c = float2(0.06 * sin(ph * 5.0 + float(i)), 0.50 + ph * 0.45);
        d = min(d, length(p - float3(c, 0)) - (0.08 + 0.10 * ph));
    }
    return d;
}

ORB_FORMA(vulcano)
