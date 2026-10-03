#include "../OrbShading.h"

// Mail · spedizioni: a delivery van in profile, its wheels rings with turning spokes.
static float furgone(float3 p, float t) {
    float d = sdRoundBox2(p.xy - float2(-0.20, 0.10), float2(0.5, 0.42), 0.06);
    d = min(d, sdQuad2(p.xy, float2(0.30, -0.32), float2(0.88, -0.32), float2(0.62, 0.34), float2(0.30, 0.34)));
    for (int w = 0; w < 2; w++) {
        float2 c = p.xy - float2(w == 0 ? -0.45 : 0.58, -0.45);
        d = min(d, abs(length(c) - 0.17) - 0.035);
        for (int k = 0; k < 3; k++) {
            float a = -t * 3.0 + float(k) * 2.0944;
            d = min(d, udSegment2(c, float2(0), 0.15 * float2(cos(a), sin(a))) - 0.025);
        }
    }
    return extrude(d, p.z, 0.07) - 0.03;
}

ORB_FORMA(furgone)
