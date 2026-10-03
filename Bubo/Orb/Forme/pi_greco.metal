#include "../OrbShading.h"

// Chat · matematica: the letter pi in relief, a thick bar over two legs, the right one hooked at the foot.
static float pi_greco(float3 p, float) {
    float d2 = udSegment2(p.xy, float2(-0.72, 0.5), float2(0.72, 0.5));
    d2 = min(d2, udSegment2(p.xy, float2(-0.35, 0.5), float2(-0.45, -0.7)));
    d2 = min(d2, udSegment2(p.xy, float2(0.3, 0.5), float2(0.3, -0.45)));
    d2 = min(d2, udSegment2(p.xy, float2(0.3, -0.45), float2(0.52, -0.7)));
    return extrude(d2 - 0.06, p.z, 0.04) - 0.04;
}

ORB_FORMA(pi_greco)
