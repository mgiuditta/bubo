#include "../OrbShading.h"

// Viaggi: two skis crossed in an X, with a ski pole on each side ending in a basket.
static float sci(float3 p, float) {
    float3 a = p, b = p;
    a.xy = a.xy * rot(0.5);
    b.xy = b.xy * rot(-0.5);
    float d = min(sdRoundBox(a, float3(0.09, 0.85, 0.04), 0.03), sdRoundBox(b, float3(0.09, 0.85, 0.04), 0.03));
    for (int i = 0; i < 2; i++) {
        float side = i == 0 ? -1.0 : 1.0;
        float3 top = float3(0.45 * side, 0.8, -0.05), bottom = float3(0.55 * side, -0.85, -0.05);
        float3 basket = mix(top, bottom, 0.909);
        float3 q = p - basket;
        d = min(d, min(sdSegment(p, top, bottom, 0.035), length(p - top) - 0.07));
        d = min(d, length(float2(length(q.xz) - 0.11, q.y)) - 0.022);
    }
    return d;
}

ORB_FORMA(sci)
