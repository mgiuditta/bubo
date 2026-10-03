#include "../OrbShading.h"

// Codice · verifica: a blackboard with a chalk zigzag and a tray, on a three-legged easel.
static float lavagna(float3 p, float) {
    float2 c = p.xy - float2(0, 0.22);
    float frame = extrude(abs(sdRoundBox2(c, float2(0.64, 0.44), 0.06)) - 0.06, p.z, 0.06);
    float board = sdRoundBox(p - float3(0, 0.22, -0.02), float3(0.6, 0.4, 0.02), 0.02);
    float tray = sdRoundBox(p - float3(0, -0.34, 0.1), float3(0.5, 0.03, 0.1), 0.02);
    float d = min(min(frame, board), tray);
    const float2 chalk[4] = { float2(-0.4, 0.45), float2(-0.1, 0.2), float2(0.1, 0.4), float2(0.4, 0.15) };
    for (int i = 0; i < 3; i++) {
        d = min(d, sdSegment(p, float3(chalk[i], 0.04), float3(chalk[i + 1], 0.04), 0.03));
    }
    float3 q = float3(abs(p.x), p.y, p.z);
    d = min(d, sdSegment(q, float3(0.35, -0.3, 0), float3(0.55, -0.9, 0), 0.04));
    return min(d, sdSegment(p, float3(0, -0.3, -0.05), float3(0, -0.9, -0.3), 0.04));
}

ORB_FORMA(lavagna)
