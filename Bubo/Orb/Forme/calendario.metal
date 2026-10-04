#include "../OrbShading.h"

// Tempo: a desk calendar leaning back a little, a raised header and two rings on top, days as dots.
static float calendario(float3 p, float) {
    p.yz = p.yz * rot(-0.18);
    p.y += 0.06;
    float board = sdRoundBox(p - float3(0, -0.08, 0), float3(0.72, 0.62, 0.07), 0.06);
    float header = sdRoundBox(p - float3(0, 0.39, 0.03), float3(0.72, 0.15, 0.08), 0.06);
    float3 q = float3(abs(p.x) - 0.36, p.y - 0.58, p.z);
    float rings = length(float2(length(q.yz) - 0.15, q.x)) - 0.045;
    float d = min(min(board, header), rings);
    for (int row = 0; row < 3; row++) {
        for (int col = 0; col < 4; col++) {
            d = min(d, length(p - float3(-0.45 + 0.30 * float(col), 0.04 - 0.24 * float(row), 0.07)) - 0.065);
        }
    }
    return d;
}

ORB_FORMA(calendario)
