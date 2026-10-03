#include "../OrbShading.h"

// Musica · danza: a ballet shoe in profile with a rounded toe and two ribbons winding up from the ankle.
static float scarpetta(float3 p, float) {
    p.y += 0.05;
    float2 q = p.xy;
    float shoe = udSegment2(q, float2(-0.45, -0.28), float2(0.5, -0.42)) - 0.27;
    float ankle = udSegment2(q, float2(-0.5, -0.1), float2(-0.38, 0.45)) - 0.18;
    float sole = udSegment2(q, float2(-0.62, -0.62), float2(0.6, -0.72)) - 0.05;
    float ribbon1 = min(udSegment2(q, float2(-0.4, 0.4), float2(0.02, 0.0)), udSegment2(q, float2(0.02, 0.0), float2(0.3, -0.3))) - 0.045;
    float ribbon2 = min(udSegment2(q, float2(-0.4, 0.4), float2(-0.8, 0.0)), udSegment2(q, float2(-0.8, 0.0), float2(-0.8, -0.5))) - 0.045;
    return extrude(min(min(shoe, ankle), min(sole, min(ribbon1, ribbon2))), p.z, 0.07) - 0.03;
}

ORB_FORMA(scarpetta)
