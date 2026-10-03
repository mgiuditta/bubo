#include "../OrbShading.h"

// Ricerca · appunti: a notebook, a page with a spiral of rings along the top and ruled lines in relief.
static float taccuino(float3 p, float) {
    float d = sdRoundBox2(p.xy - float2(0, -0.10), float2(0.5, 0.62), 0.06);
    for (int i = 0; i < 4; i++) d = min(d, abs(length(p.xy - float2(-0.45 + 0.30 * float(i), 0.56)) - 0.07) - 0.02);
    float solid = extrude(d, p.z, 0.06) - 0.03;
    for (int i = 0; i < 3; i++) {
        float y = 0.25 - 0.28 * float(i);
        solid = min(solid, sdSegment(p, float3(-0.28, y, 0.10), float3(0.28, y, 0.10), 0.025));
    }
    return solid;
}

ORB_FORMA(taccuino)
