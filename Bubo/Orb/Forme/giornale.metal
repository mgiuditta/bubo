#include "../OrbShading.h"

// Ricerca: a newspaper folded in two, its pages tilted back from the fold; a headline, a picture and columns.
static float giornale(float3 p, float) {
    float3 q = float3(abs(p.x), p.y, p.z);
    q.xz = q.xz * rot(0.2);
    float page = sdRoundBox(q - float3(0.44, 0, 0), float3(0.44, 0.64, 0.03), 0.03);
    float head = sdSegment(q, float3(0.10, 0.50, 0.06), float3(0.76, 0.50, 0.06), 0.045);
    float picture = sdRoundBox(q - float3(0.28, 0.14, 0.06), float3(0.16, 0.14, 0.015), 0.01);
    float d = min(min(page, head), picture);
    for (int i = 0; i < 3; i++) {
        float y = 0.18 - 0.16 * float(i);
        d = min(d, sdSegment(q, float3(0.54, y, 0.06), float3(0.76, y, 0.06), 0.025));
        d = min(d, sdSegment(q, float3(0.12, -0.20 - 0.14 * float(i), 0.06), float3(0.76, -0.20 - 0.14 * float(i), 0.06), 0.025));
    }
    return d;
}

ORB_FORMA(giornale)
