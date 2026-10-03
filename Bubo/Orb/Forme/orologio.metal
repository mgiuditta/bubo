#include "../OrbShading.h"

// Tempo · ora: a wristwatch, a round case with a crown and two straps, hour marks and hands; the second hand sweeps.
static float orologio(float3 p, float t) {
    float3 q = float3(abs(p.x), abs(p.y), p.z);
    float cs = extrude(length(p.xy) - 0.38, p.z, 0.06) - 0.10;
    float strap = sdRoundBox(q - float3(0, 0.68, -0.02), float3(0.20, 0.22, 0.04), 0.04);
    float crown = sdRoundBox(p - float3(0.52, 0, 0), float3(0.06, 0.07, 0.06), 0.02);
    float d = min(min(cs, strap), crown);
    d = min(d, length(q - float3(0.0, 0.40, 0.14)) - 0.035);
    d = min(d, length(q - float3(0.40, 0.0, 0.14)) - 0.035);
    d = min(d, sdSegment(p, float3(0, 0, 0.16), float3(0, 0.30, 0.16), 0.035));
    d = min(d, sdSegment(p, float3(0, 0, 0.16), float3(0.17, 0.0, 0.16), 0.035));
    d = min(d, sdSegment(p, float3(0, 0, 0.19), float3(sin(t), cos(t), 0) * 0.34 + float3(0, 0, 0.19), 0.02));
    return d;
}

ORB_FORMA(orologio)
