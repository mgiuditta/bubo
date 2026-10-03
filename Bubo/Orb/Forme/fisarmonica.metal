#include "../OrbShading.h"

// Musica · musica popolare: an accordion, two end boxes with pleated bellows between them that open and close.
static float fisarmonica(float3 p, float t) {
    float g = 0.12 + 0.03 * sin(t * 0.9);
    float d = 1e3;
    for (int i = 0; i < 8; i++) {
        float x = (float(i) - 3.5) * g;
        float h = i % 2 == 0 ? 0.34 : 0.26;
        d = min(d, sdSegment(p, float3(x, -h, 0), float3(x, h, 0), 0.035));
        if (i < 7) {
            float x1 = x + g, h1 = i % 2 == 0 ? 0.26 : 0.34;
            d = min(d, sdSegment(p, float3(x, h, 0), float3(x1, h1, 0), 0.035));
            d = min(d, sdSegment(p, float3(x, -h, 0), float3(x1, -h1, 0), 0.035));
        }
    }
    float ends = sdRoundBox2(float2(abs(p.x) - (3.5 * g + 0.16), p.y), float2(0.14, 0.45), 0.04);
    return min(d, extrude(ends, p.z, 0.10) - 0.03);
}

ORB_FORMA(fisarmonica)
