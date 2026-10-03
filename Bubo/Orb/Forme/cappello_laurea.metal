#include "../OrbShading.h"

// Chat · conversazione: a graduation cap, the flat board over the cap, a tassel that swings from one corner.
static float cappello_laurea(float3 p, float t) {
    float board = extrude(sdQuad2(p.xy, float2(0, 0.45), float2(1.0, 0.12), float2(0, -0.2), float2(-1.0, 0.12)), p.z, 0.03) - 0.03;
    float cap = extrude(sdQuad2(p.xy, float2(-0.5, -0.1), float2(0.5, -0.1), float2(0.42, -0.55), float2(-0.42, -0.55)), p.z, 0.08) - 0.04;
    float cord = sdSegment(p, float3(0, 0.15, 0.03), float3(0.9, 0.12, 0.03), 0.03);
    float3 q = p - float3(0.9, 0.12, 0.03);
    q.xy = q.xy * rot(0.22 * sin(t * 2.0));
    float hang = sdSegment(q, float3(0, 0, 0), float3(0, -0.5, 0), 0.03);
    float tassel = sdRoundCone(q, float3(0, -0.45, 0), float3(0, -0.75, 0), 0.04, 0.11);
    return min(min(board, cap), min(cord, min(hang, tassel)));
}

ORB_FORMA(cappello_laurea)
