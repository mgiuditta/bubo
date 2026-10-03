#include "../OrbShading.h"

// Chat · unire documenti: a desk stapler in profile whose arm presses down and lifts again on its hinge.
static float spillatrice(float3 p, float t) {
    const float2 hinge = float2(-0.7, -0.25);
    float open = 0.32 * (0.5 + 0.5 * cos(t * 1.8));
    float base = sdRoundBox2(p.xy - float2(0.0, -0.48), float2(0.78, 0.1), 0.06);
    float2 a = (p.xy - hinge) * rot(-open);
    float arm = sdRoundBox2(a - float2(0.75, 0.12), float2(0.78, 0.13), 0.08);
    float nose = length(a - float2(1.55, 0.1)) - 0.14;
    float pin = udSegment2(p.xy, hinge, hinge + float2(0, -0.1)) - 0.09;
    return extrude(min(min(base, arm), min(nose, pin)), p.z, 0.16) - 0.04;
}

ORB_FORMA(spillatrice)
