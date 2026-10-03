#include "../OrbShading.h"

// Mail: a paper clip, three nested loops of wire.
static float graffetta(float3 p, float) {
    float2 q = p.xy - float2(0, -0.04);
    const float2 L = float2(-1, 1), R = float2(1, 1), LL = float2(-1, -1), RL = float2(1, -1);
    float w = udSegment2(q, float2(-0.14, -0.30), float2(-0.14, 0.30));                 // inner tail up
    w = min(w, min(udQuarterArc(q, float2(0, 0.30), 0.14, L), udQuarterArc(q, float2(0, 0.30), 0.14, R)));
    w = min(w, udSegment2(q, float2(0.14, 0.30), float2(0.14, -0.50)));                 // down the inner side
    w = min(w, min(udQuarterArc(q, float2(-0.10, -0.50), 0.24, LL), udQuarterArc(q, float2(-0.10, -0.50), 0.24, RL)));
    w = min(w, udSegment2(q, float2(-0.34, -0.50), float2(-0.34, 0.50)));               // up the outer side
    w = min(w, min(udQuarterArc(q, float2(0, 0.50), 0.34, L), udQuarterArc(q, float2(0, 0.50), 0.34, R)));
    w = min(w, udSegment2(q, float2(0.34, 0.50), float2(0.34, -0.20)));                 // outer tail down
    return extrude(w - 0.02, p.z, 0.01) - 0.03;
}

ORB_FORMA(graffetta)
