#include "../OrbShading.h"

// Finanza: a paper shopping bag widening toward the top, two handles and a baguette sticking out.
static float borsa_spesa(float3 p, float) {
    float bag = extrude(sdQuad2(p.xy, float2(-0.55, -0.75), float2(0.55, -0.75), float2(0.65, 0.3), float2(-0.65, 0.3)), p.z, 0.2) - 0.04;
    float front = sdTorusXY(p - float3(-0.25, 0.3, 0.15), 0.2, 0.04);
    float back = sdTorusXY(p - float3(-0.25, 0.3, -0.15), 0.2, 0.04);
    float bread = sdSegment(p, float3(0.1, 0.05, 0), float3(0.5, 0.8, 0), 0.1);
    return min(min(bag, bread), min(front, back));
}

ORB_FORMA(borsa_spesa)
