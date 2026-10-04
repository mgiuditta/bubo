#include "../OrbShading.h"

// Creativo: a jester's hat, a band with three curling points that end in bells; the bells swing.
static float cappello_giullare(float3 p, float t) {
    float3 q = float3(abs(p.x), p.y, p.z);
    float band = sdRoundBox(p - float3(0, -0.5, 0), float3(0.45, 0.12, 0.18), 0.08);
    float side = sdRoundCone(q, float3(0.3, -0.4, 0), float3(0.62, 0.42, 0), 0.15, 0.05);
    float middle = sdRoundCone(p, float3(0, -0.4, 0), float3(0, 0.68, 0), 0.15, 0.05);
    float bellSide = length(q - float3(0.62 + 0.06 * sin(t * 5.0), 0.42, 0)) - 0.1;
    float bellMiddle = length(p - float3(0.06 * sin(t * 6.1), 0.68, 0)) - 0.1;
    return min(min(band, side), min(middle, min(bellSide, bellMiddle)));
}

ORB_FORMA(cappello_giullare)
