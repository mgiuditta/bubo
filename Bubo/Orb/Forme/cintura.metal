#include "../OrbShading.h"

// Salute · arti marziali: a belt tied in a knot, the band running out to both sides and two loose ends hanging down.
static float cintura(float3 p, float) {
    p.y -= 0.22;
    float2 q = p.xy;
    float band = min(udSegment2(q, float2(-0.88, 0.3), float2(-0.15, 0.2)), udSegment2(q, float2(0.15, 0.2), float2(0.88, 0.3))) - 0.1;
    float knot = sdRoundBox2(q - float2(0, 0.2), float2(0.17, 0.15), 0.09);
    float tails = min(udSegment2(q, float2(-0.08, 0.05), float2(-0.4, -0.72)), udSegment2(q, float2(0.08, 0.05), float2(0.32, -0.78))) - 0.095;
    return extrude(min(band, min(knot, tails)), p.z, 0.05) - 0.04;
}

ORB_FORMA(cintura)
