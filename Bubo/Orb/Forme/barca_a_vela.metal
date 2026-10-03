#include "../OrbShading.h"

// Viaggi · barca a vela: a hull with two triangular sails, heeling over with the wind.
static float barca_a_vela(float3 p, float t) {
    p.xy -= float2(0, -0.45);
    p.xy = p.xy * rot(0.1 + 0.07 * sin(t * 0.9));
    p.xy += float2(0, -0.45);
    float hull = sdQuad2(p.xy, float2(-0.7, -0.5), float2(0.7, -0.5), float2(0.45, -0.8), float2(-0.42, -0.8));
    float mast = udSegment2(p.xy, float2(0, -0.5), float2(0, 0.92)) - 0.035;
    float sail = sdQuad2(p.xy, float2(0.12, 0.9), float2(0.12, -0.38), float2(0.66, -0.38), float2(0.34, 0.22));
    float jib = sdQuad2(p.xy, float2(-0.12, 0.7), float2(-0.12, -0.38), float2(-0.6, -0.38), float2(-0.34, 0.1));
    return extrude(min(min(hull, mast), min(sail, jib)), p.z, 0.04) - 0.02;
}

ORB_FORMA(barca_a_vela)
