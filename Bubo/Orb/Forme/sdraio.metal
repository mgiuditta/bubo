#include "../OrbShading.h"

// Tempo · ferie: a deck chair in profile, a sloped back and seat of canvas on an A of legs, with an armrest.
static float sdraio(float3 p, float) {
    float cloth = min(udSegment2(p.xy, float2(-0.60, 0.75), float2(-0.15, -0.20)),
                      udSegment2(p.xy, float2(-0.15, -0.20), float2(0.60, -0.30))) - 0.08;
    float frame = min(udSegment2(p.xy, float2(-0.20, -0.15), float2(-0.45, -0.80)),
                      min(udSegment2(p.xy, float2(0.20, 0.15), float2(0.35, -0.80)),
                          udSegment2(p.xy, float2(-0.35, 0.25), float2(0.20, 0.15)))) - 0.045;
    return extrude(min(cloth, frame), p.z, 0.04) - 0.03;
}

ORB_FORMA(sdraio)
