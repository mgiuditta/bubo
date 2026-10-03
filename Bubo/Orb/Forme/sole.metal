#include "../OrbShading.h"

// Meteo: a disc with eight short rays, turning slowly.
static float sole(float3 p, float t) {
    float d = extrude(length(p.xy) - 0.36, p.z, 0.08) - 0.08;
    for (int i = 0; i < 8; i++) {
        float a = 0.7853982 * float(i) + t * 0.25;
        float2 dir = float2(cos(a), sin(a));
        d = min(d, sdSegment(p, float3(dir * 0.62, 0), float3(dir * 0.88, 0), 0.06));
    }
    return d;
}

ORB_FORMA(sole)
