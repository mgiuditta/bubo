#include "../OrbShading.h"

// Agente · computer: the mouse pointer arrow, slanted; now and then it clicks a little forward.
static float puntatore(float3 p, float t) {
    float k = 0.08 * pulse(fract(t / 2.5), 0.10, 0.08);
    float2 c = p.xy - k * float2(-0.5, 0.86);
    float head = sdQuad2(c, float2(-0.45, 0.85), float2(-0.45, -0.45), float2(-0.025, -0.275), float2(0.40, -0.10));
    float tail = udSegment2(c, float2(-0.05, -0.30), float2(0.22, -0.82)) - 0.09;
    return extrude(min(head, tail), p.z, 0.04) - 0.03;
}

ORB_FORMA(puntatore)
