#include "../OrbShading.h"

// Chat · conversazione: a necktie, a small knot over a long blade that ends in a point.
static float cravatta(float3 p, float) {
    float knot = extrude(sdQuad2(p.xy, float2(-0.2, 0.8), float2(0.2, 0.8), float2(0.14, 0.45), float2(-0.14, 0.45)), p.z, 0.08) - 0.04;
    float blade = extrude(sdQuad2(p.xy, float2(-0.14, 0.45), float2(0.14, 0.45), float2(0.3, -0.5), float2(-0.3, -0.5)), p.z, 0.05) - 0.04;
    float tip = extrude(sdQuad2(p.xy, float2(-0.3, -0.5), float2(0.3, -0.5), float2(0.04, -0.9), float2(-0.04, -0.9)), p.z, 0.05) - 0.04;
    return min(knot, min(blade, tip));
}

ORB_FORMA(cravatta)
