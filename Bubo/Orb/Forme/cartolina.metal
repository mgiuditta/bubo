#include "../OrbShading.h"

// Mail: a postcard, a slab with a stamp and postmark at the top right, address lines on the right and message lines on the left.
static float cartolina(float3 p, float) {
    p.xy = p.xy * rot(0.1);
    float d = sdRoundBox(p, float3(0.82, 0.55, 0.04), 0.03);
    d = min(d, sdRoundBox(p - float3(0.60, 0.33, 0.06), float3(0.14, 0.16, 0.02), 0.01));
    d = min(d, sdTorusXY(p - float3(0.33, 0.30, 0.05), 0.11, 0.02));
    d = min(d, sdSegment(p, float3(-0.02, -0.40, 0.045), float3(-0.02, 0.40, 0.045), 0.018));
    for (int i = 0; i < 3; i++) {
        float y = -0.16 * float(i);
        d = min(d, sdSegment(p, float3(0.15, y, 0.045), float3(0.72, y, 0.045), 0.02));
        float m = 0.30 - 0.20 * float(i);
        d = min(d, sdSegment(p, float3(-0.72, m, 0.045), float3(-0.22, m, 0.045), 0.02));
    }
    return d;
}

ORB_FORMA(cartolina)
