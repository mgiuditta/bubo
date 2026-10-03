#include "../OrbShading.h"

// Creativo · carta: an origami crane facing right, folded body, one raised wing, neck, beak and tail.
static float origami(float3 p, float) {
    float body = sdQuad2(p.xy, float2(-0.40, -0.10), float2(0.05, -0.45), float2(0.45, -0.05), float2(0.05, 0.20));
    float wing = sdQuad2(p.xy, float2(-0.30, 0.0), float2(-0.55, 0.80), float2(0.25, 0.15), float2(-0.025, 0.075));
    float neck = udSegment2(p.xy, float2(0.38, -0.05), float2(0.72, 0.45)) - 0.05;
    float beak = sdQuad2(p.xy, float2(0.66, 0.38), float2(0.70, 0.62), float2(0.95, 0.42), float2(0.805, 0.40));
    float tail = udSegment2(p.xy, float2(-0.40, -0.10), float2(-0.85, 0.15)) - 0.04;
    return extrude(min(min(body, wing), min(neck, min(beak, tail))), p.z, 0.04) - 0.03;
}

ORB_FORMA(origami)
