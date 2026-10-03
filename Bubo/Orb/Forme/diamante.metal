#include "../OrbShading.h"

// Finanza · beni di lusso: a brilliant-cut gem seen from the side, with facet lines; it spins around its axis.
static float diamante(float3 p, float t) {
    float3 q = p;
    q.xz = p.xz * rot(t * 0.8);
    float2 a = float2(-0.8, 0.1), b = float2(0.8, 0.1), c = float2(0, -0.85);
    float crown = sdQuad2(q.xy, float2(-0.4, 0.45), float2(0.4, 0.45), float2(0.8, 0.1), float2(-0.8, 0.1));
    float pavilion = sdQuad2(q.xy, a, b, c, 0.5 * (c + a));
    float gem = extrude(min(crown, pavilion), q.z, 0.18) - 0.02;
    float facets = min(min(sdSegment(q, float3(-0.4, 0.45, 0.2), float3(-0.3, 0.1, 0.2), 0.025),
                           sdSegment(q, float3(0.4, 0.45, 0.2), float3(0.3, 0.1, 0.2), 0.025)),
                       min(sdSegment(q, float3(-0.3, 0.1, 0.2), float3(0, -0.85, 0.2), 0.025),
                           sdSegment(q, float3(0.3, 0.1, 0.2), float3(0, -0.85, 0.2), 0.025)));
    return min(gem, facets);
}

ORB_FORMA(diamante)
