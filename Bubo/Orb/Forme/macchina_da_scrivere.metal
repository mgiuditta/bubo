#include "../OrbShading.h"

// Creativo · racconti: a typewriter, a trapezoid body with a row of keys and the carriage with its paper sliding along.
static float macchina_da_scrivere(float3 p, float t) {
    float d = sdQuad2(p.xy, float2(-0.70, -0.75), float2(0.70, -0.75), float2(0.55, -0.10), float2(-0.55, -0.10));
    float2 c = p.xy - float2(0.12 * sin(t * 0.9), 0);
    d = min(d, udSegment2(c, float2(-0.75, -0.02), float2(0.75, -0.02)) - 0.08);
    d = min(d, length(c - float2(-0.82, -0.02)) - 0.10);
    d = min(d, length(c - float2(0.82, -0.02)) - 0.10);
    d = min(d, sdRoundBox2(c - float2(0, 0.40), float2(0.32, 0.40), 0.02));
    float solid = extrude(d, p.z, 0.06) - 0.03;
    for (int i = 0; i < 5; i++) solid = min(solid, length(p - float3(-0.4 + 0.2 * float(i), -0.40, 0.12)) - 0.06);
    return solid;
}

ORB_FORMA(macchina_da_scrivere)
