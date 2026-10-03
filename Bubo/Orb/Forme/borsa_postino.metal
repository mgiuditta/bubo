#include "../OrbShading.h"

// Mail · posta arretrata: a messenger bag with its pointed flap, a buckle and a strap over the top.
static float borsa_postino(float3 p, float) {
    float body = sdRoundBox(p - float3(0, -0.3, 0), float3(0.7, 0.45, 0.2), 0.1);
    float2 a = float2(-0.72, -0.2), b = float2(0.72, -0.2), c = float2(0, -0.55);
    float flap2 = min(sdRoundBox2(p.xy - float2(0, -0.025), float2(0.72, 0.175), 0.0), sdQuad2(p.xy, a, b, c, 0.5 * (c + a)));
    float flap = extrude(flap2, p.z - 0.22, 0.03);
    float buckle = sdRoundBox(p - float3(0, -0.42, 0.27), float3(0.06, 0.06, 0.02), 0.02);
    const float2 centre = float2(0, 0.1);
    float strap = min(udQuarterArc(p.xy, centre, 0.65, float2(1, 1)), udQuarterArc(p.xy, centre, 0.65, float2(-1, 1))) - 0.045;
    return min(min(body, flap), min(buckle, extrude(strap, p.z, 0.03)));
}

ORB_FORMA(borsa_postino)
