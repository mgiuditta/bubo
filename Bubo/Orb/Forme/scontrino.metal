#include "../OrbShading.h"

// Finanza: a long receipt with a saw-toothed bottom edge and five raised lines of print.
static float scontrino(float3 p, float) {
    p.y -= 0.07;
    float2 q = p.xy;
    float d = sdRoundBox2(q - float2(0, 0.1), float2(0.34, 0.70), 0.0);
    for (int i = 0; i < 5; i++) {
        float2 c = q - float2(-0.272 + 0.136 * float(i), -0.60);
        d = min(d, sdRoundBox2(float2(c.x + c.y, c.y - c.x) * 0.70710678, float2(0.048), 0.0));
    }
    float slab = extrude(d, p.z, 0.04);
    for (int i = 0; i < 5; i++) {
        float y = 0.55 - 0.20 * float(i);
        float w = 0.30 + 0.07 * float((i * 2) % 3);
        slab = min(slab, sdSegment(p, float3(-0.22, y, 0.06), float3(-0.22 + w, y, 0.06), 0.03));
    }
    return slab;
}

ORB_FORMA(scontrino)
