#include "../OrbShading.h"

// Creativo · foto e immagini: a thick picture frame holding a little mountain and a sun.
static float cornice(float3 p, float) {
    float ring = abs(sdRoundBox2(p.xy, float2(0.85, 0.65), 0.06) + 0.13) - 0.13;
    float frame = extrude(ring, p.z, 0.08) - 0.03;
    float2 a = float2(-0.45, -0.3), b = float2(0.05, -0.3), c = float2(-0.2, 0.12);
    float hill = sdQuad2(p.xy, a, b, c, 0.5 * (c + a));
    float picture = extrude(min(hill, length(p.xy - float2(0.28, 0.15)) - 0.1), p.z, 0.04);
    return min(frame, picture);
}

ORB_FORMA(cornice)
