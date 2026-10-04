#include "../OrbShading.h"

// Chat · rompicapo: a chess knight facing left, on a round base.
static float cavallo_scacchi(float3 p, float) {
    float base = sdRoundBox2(p.xy - float2(0, -0.80), float2(0.46, 0.07), 0.06);
    float body = sdQuad2(p.xy, float2(-0.32, -0.72), float2(0.40, -0.72), float2(0.36, 0.0), float2(-0.20, 0.0));
    float neck = sdQuad2(p.xy, float2(-0.24, -0.05), float2(0.36, -0.05), float2(0.30, 0.60), float2(-0.02, 0.70));
    float head = sdQuad2(p.xy, float2(-0.64, 0.02), float2(-0.10, 0.76), float2(0.30, 0.62), float2(-0.02, 0.10));
    float ear = sdQuad2(p.xy, float2(-0.02, 0.74), float2(0.06, 0.98), float2(0.18, 0.68), float2(0.08, 0.71));
    return extrude(min(min(base, body), min(neck, min(head, ear))), p.z, 0.05) - 0.04;
}

ORB_FORMA(cavallo_scacchi)
