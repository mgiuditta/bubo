#include "../OrbShading.h"

// Salute · movimento: a running shoe in profile, toe to the right, high heel and a thick sole.
static float scarpa_da_corsa(float3 p, float) {
    float2 q = p.xy - float2(0, 0.10);
    float heel = sdQuad2(q, float2(-0.80, -0.30), float2(-0.80, 0.34), float2(0.00, 0.22), float2(0.05, -0.30));
    float vamp = sdQuad2(q, float2(-0.10, -0.30), float2(-0.10, 0.22), float2(0.30, 0.02), float2(0.86, -0.30));
    float sole = sdRoundBox2(q - float2(0.02, -0.41), float2(0.88, 0.10), 0.08);
    return extrude(min(min(heel, vamp), sole), p.z, 0.14) - 0.04;
}

ORB_FORMA(scarpa_da_corsa)
