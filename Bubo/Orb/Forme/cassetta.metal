#include "../OrbShading.h"

// Musica: an audio cassette, a flat case with a trapezoid at the bottom and two reels whose spokes turn.
static float cassetta(float3 p, float t) {
    float body = sdRoundBox(p - float3(0, 0.12, 0), float3(0.88, 0.5, 0.08), 0.06);
    float foot = extrude(sdQuad2(p.xy, float2(-0.6, -0.3), float2(0.6, -0.3), float2(0.42, -0.7), float2(-0.42, -0.7)), p.z, 0.08) - 0.02;
    float d = min(body, foot);
    for (int k = 0; k < 2; k++) {
        float3 q = p - float3(k == 0 ? -0.4 : 0.4, 0.25, 0.1);
        d = min(d, min(sdTorusXY(q, 0.2, 0.035), length(q) - 0.06));
        for (int s = 0; s < 3; s++) {
            float a = t * (k == 0 ? 1.4 : 1.8) + float(s) * 2.0944;
            d = min(d, sdSegment(q, float3(0), float3(cos(a), sin(a), 0) * 0.2, 0.03));
        }
    }
    return d;
}

ORB_FORMA(cassetta)
