#include "../OrbShading.h"

// Chat · casa: a slice of pizza, tip down, with a thick crust and four pepperoni.
static float pizza(float3 p, float) {
    float slice = sdQuad2(p.xy, float2(0, -0.80), float2(0.55, 0.45), float2(0, 0.50), float2(-0.55, 0.45));
    float d = extrude(slice, p.z, 0.06) - 0.01;
    float crust = min(min(sdSegment(p, float3(-0.55, 0.52, 0), float3(-0.28, 0.59, 0), 0.10), sdSegment(p, float3(-0.28, 0.59, 0), float3(0, 0.62, 0), 0.10)),
                      min(sdSegment(p, float3(0, 0.62, 0), float3(0.28, 0.59, 0), 0.10), sdSegment(p, float3(0.28, 0.59, 0), float3(0.55, 0.52, 0), 0.10)));
    float peps = min(min(length(p - float3(-0.15, 0.22, 0.06)) - 0.10, length(p - float3(0.18, 0.02, 0.06)) - 0.10),
                     min(length(p - float3(-0.05, -0.28, 0.06)) - 0.09, length(p - float3(0.12, 0.38, 0.06)) - 0.09));
    return min(min(d, crust), peps);
}

ORB_FORMA(pizza)
