#include "../OrbShading.h"

// Salute · movimento: a yoga mat rolled up, seen from the side; a little of it unrolls and rolls back.
static float tappetino(float3 p, float t) {
    float len = 0.65 + 0.3 * sin(t * 1.2);
    float roll = extrude(length(p.xy - float2(-0.3, 0)) - 0.45, p.z, 0.3);
    float strip = extrude(sdRoundBox2(p.xy - float2(-0.3 + len * 0.5, -0.42), float2(len * 0.5, 0.03), 0.02), p.z, 0.3);
    return min(roll, strip);
}

ORB_FORMA(tappetino)
