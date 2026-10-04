#include "../OrbShading.h"

// Salute · sport sulle onde: a surfboard standing upright, seen from below, with its stringer and the fin near the tail.
static float surf(float3 p, float) {
    p.xy = p.xy * rot(-0.18);
    float board = sdQuad2(p.xy, float2(0, -0.88), float2(0.27, -0.1), float2(0, 0.92), float2(-0.27, -0.1)) - 0.06;
    float shape = extrude(board, p.z, 0.04) - 0.02;
    float stringer = sdSegment(p, float3(0, -0.7, 0.09), float3(0, 0.78, 0.09), 0.03);
    float fin = extrude(sdQuad2(p.xy, float2(-0.11, -0.7), float2(0.11, -0.7), float2(0.03, -0.3), float2(-0.03, -0.3)), p.z - 0.1, 0.03) - 0.02;
    return min(shape, min(stringer, fin));
}

ORB_FORMA(surf)
