#include "../OrbShading.h"

// Salute · regole dello sport e arbitri: a referee's whistle, a round chamber and a mouthpiece, with a lanyard loop.
static float fischietto(float3 p, float) {
    p.x += 0.07;
    p.y += 0.1;
    float2 q = p.xy;
    float chamber = length(q - float2(-0.2, -0.05)) - 0.38;
    float mouth = sdRoundBox2(q - float2(0.42, 0.02), float2(0.4, 0.17), 0.07);
    float hole = udSegment2(q, float2(-0.1, 0.3), float2(0.1, 0.3)) - 0.03;
    float shape = extrude(min(chamber, min(mouth, hole)), p.z, 0.12) - 0.04;
    float lanyard = sdTorusXY(p - float3(-0.58, 0.5, 0), 0.3, 0.035);
    float ring = sdTorusXY(p - float3(-0.34, 0.36, 0), 0.07, 0.03);
    return min(shape, min(lanyard, ring));
}

ORB_FORMA(fischietto)
