#include "../OrbShading.h"

// Creativo: a clapperboard, the clapper open and shutting again and again.
static float ciak(float3 p, float t) {
    float body = extrude(sdRoundBox2(p.xy - float2(0, -0.30), float2(0.70, 0.40), 0.03), p.z, 0.07) - 0.03;
    float lines = min(sdSegment(p, float3(-0.45, -0.18, 0.10), float3(0.30, -0.18, 0.10), 0.035),
                      sdSegment(p, float3(-0.45, -0.42, 0.10), float3(0.45, -0.42, 0.10), 0.035));
    const float2 pivot = float2(-0.70, 0.22);
    float angle = 0.22 * (1.0 + cos(t * 2.2));         // t = 0 is wide open
    float2 q = (p.xy - pivot) * rot(-angle);
    float clapper = extrude(sdRoundBox2(q - float2(0.70, 0), float2(0.70, 0.11), 0.02), p.z, 0.07) - 0.03;
    return min(min(body, lines), clapper);
}

ORB_FORMA(ciak)
