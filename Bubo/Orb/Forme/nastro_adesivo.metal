#include "../OrbShading.h"

// Codice · rilascio: a roll of adhesive tape seen from the side, a loose strip hanging from its edge.
static float nastro_adesivo(float3 p, float) {
    float2 c = p.xy - float2(-0.1, 0.2);
    float ring = extrude(abs(length(c) - 0.45) - 0.16, p.z, 0.10) - 0.04;
    float strip = sdRoundBox(p - float3(0.4, -0.5, 0), float3(0.13, 0.3, 0.02), 0.015);
    return min(ring, strip);
}

ORB_FORMA(nastro_adesivo)
