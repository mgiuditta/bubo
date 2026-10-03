#include "../OrbShading.h"

// Mail: an address book with three binder rings down the left edge and four staggered index tabs on the right.
static float rubrica(float3 p, float) {
    float d = sdRoundBox(p, float3(0.50, 0.70, 0.08), 0.04);
    for (int i = 0; i < 3; i++) {
        float y = -0.45 + 0.45 * float(i);
        d = min(d, length(float2(length(p.xz - float2(-0.50, 0)) - 0.14, p.y - y)) - 0.035);
    }
    for (int i = 0; i < 4; i++) {
        float y = 0.50 - 0.33 * float(i);
        d = min(d, sdRoundBox(p - float3(0.56, y, 0), float3(0.10, 0.09, 0.04), 0.02));
    }
    return d;
}

ORB_FORMA(rubrica)
