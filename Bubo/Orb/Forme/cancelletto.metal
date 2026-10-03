#include "../OrbShading.h"

// Creativo: a hash sign in relief, the uprights leaning a little.
static float cancelletto(float3 p, float) {
    float3 l = p - float3(-0.27, 0, 0), r = p - float3(0.27, 0, 0);
    l.xy = l.xy * rot(0.18);
    r.xy = r.xy * rot(0.18);
    float up = min(sdRoundBox(l, float3(0.07, 0.68, 0.09), 0.06), sdRoundBox(r, float3(0.07, 0.68, 0.09), 0.06));
    float bars = min(sdRoundBox(p - float3(0, 0.27, 0), float3(0.62, 0.07, 0.09), 0.06),
                     sdRoundBox(p - float3(0, -0.27, 0), float3(0.62, 0.07, 0.09), 0.06));
    return min(up, bars);
}

ORB_FORMA(cancelletto)
