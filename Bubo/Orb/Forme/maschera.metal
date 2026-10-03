#include "../OrbShading.h"

// Creativo: a carnival mask, a broad brow band and a narrower cheek band joined by a nose bridge and the sides,
// leaving two eye openings.
static float maschera(float3 p, float) {
    float2 q = p.xy;
    float brow = sdRoundBox2(q - float2(0, 0.3), float2(0.85, 0.15), 0.12);
    float cheeks = sdRoundBox2(q - float2(0, -0.3), float2(0.7, 0.15), 0.12);
    float bridge = sdRoundBox2(q, float2(0.14, 0.2), 0.06);
    float sides = sdRoundBox2(float2(abs(q.x) - 0.74, q.y), float2(0.11, 0.2), 0.06);
    return extrude(min(min(brow, cheeks), min(bridge, sides)), p.z, 0.06) - 0.03;
}

ORB_FORMA(maschera)
