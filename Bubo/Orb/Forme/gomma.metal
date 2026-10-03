#include "../OrbShading.h"

// Chat · conversazione: an eraser with one corner worn off and a paper sleeve, rubbing back and forth.
static float gomma(float3 p, float t) {
    p.x -= 0.07 * sin(t * 4.0);
    p.xy = p.xy * rot(0.42);
    float block = min(sdQuad2(p.xy, float2(-0.70, -0.30), float2(0.42, -0.30), float2(0.42, 0.30), float2(-0.70, 0.30)),
                      sdQuad2(p.xy, float2(0.42, -0.30), float2(0.70, -0.04), float2(0.70, 0.30), float2(0.42, 0.30)));
    const float round = 0.05;
    float rubber = extrude(block + round, p.z, 0.16) - round;
    float sleeve = sdRoundBox(p - float3(-0.30, 0, 0), float3(0.24, 0.33, 0.24), 0.03);
    return min(rubber, sleeve);
}

ORB_FORMA(gomma)
