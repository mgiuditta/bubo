#include "../OrbShading.h"

// Agente: a horseshoe magnet, a thick U with a wider cap on each pole.
static float calamita(float3 p, float) {
    const float2 c = float2(0, -0.12);
    float u = min(min(udQuarterArc(p.xy, c, 0.5, float2(-1, -1)), udQuarterArc(p.xy, c, 0.5, float2(1, -1))),
                  min(udSegment2(p.xy, float2(-0.5, -0.12), float2(-0.5, 0.5)),
                      udSegment2(p.xy, float2(0.5, -0.12), float2(0.5, 0.5))));
    float body = extrude(u - 0.12, p.z, 0.1) - 0.05;
    float cap = sdRoundBox(float3(abs(p.x) - 0.5, p.y - 0.58, p.z), float3(0.2, 0.12, 0.15), 0.04);
    return min(body, cap);
}

ORB_FORMA(calamita)
