#include "../OrbShading.h"

// Tempo · cronologie: a timeline, a line with regular ticks, three dots and a card hung on each.
static float linea_del_tempo(float3 p, float) {
    float d = udSegment2(p.xy, float2(-0.9, 0), float2(0.9, 0)) - 0.04;
    for (int k = 0; k < 11; k++) {
        if (k % 3 == 2) continue;
        float x = -0.9 + 0.18 * float(k);
        d = min(d, udSegment2(p.xy, float2(x, -0.12), float2(x, 0.12)) - 0.025);
    }
    for (int k = 0; k < 3; k++) {
        float x = 0.54 * float(k - 1);
        float y = k == 1 ? -0.45 : 0.45;
        d = min(d, length(p.xy - float2(x, 0)) - 0.14);
        d = min(d, udSegment2(p.xy, float2(x, 0), float2(x, y)) - 0.03);
        d = min(d, sdRoundBox2(p.xy - float2(x, y), float2(0.20, 0.12), 0.04));
    }
    return extrude(d, p.z, 0.05) - 0.03;
}

ORB_FORMA(linea_del_tempo)
