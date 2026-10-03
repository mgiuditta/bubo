#include "../OrbShading.h"

// Mail: an @ sign in relief: the inner ring with its stem and tail, inside an outer ring open at the lower right.
static float chiocciola(float3 p, float) {
    float2 q = p.xy;
    const float R = 0.62;
    float w = abs(length(q) - 0.24);                                     // the inner ring, a shell
    w = min(w, udSegment2(q, float2(0.30, 0.22), float2(0.30, -0.12)));  // the stem
    w = min(w, udSegment2(q, float2(0.30, -0.12), float2(0.44, -0.22))); // its tail
    w = min(w, udQuarterArc(q, float2(0), R, float2(1, 1)));
    w = min(w, udQuarterArc(q, float2(0), R, float2(-1, 1)));
    w = min(w, udQuarterArc(q, float2(0), R, float2(-1, -1)));
    return extrude(w - 0.03, p.z, 0.015) - 0.04;
}

ORB_FORMA(chiocciola)
