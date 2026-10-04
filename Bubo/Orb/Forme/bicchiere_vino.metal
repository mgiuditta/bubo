#include "../OrbShading.h"

// Chat · casa: a wine glass drawn in tube, with the wine's level a line that sloshes from side to side.
static float bicchiere_vino(float3 p, float t) {
    const float2 c = float2(0, 0.25);
    float d = sdSegment(p, float3(-0.42, 0.7, 0), float3(-0.42, 0.25, 0), 0.07);
    d = min(d, sdSegment(p, float3(0.42, 0.7, 0), float3(0.42, 0.25, 0), 0.07));
    float2 prev = c + float2(-0.42, 0);
    for (int i = 1; i <= 8; i++) {
        float a = M_PI_F + float(i) * M_PI_F / 8.0;
        float2 next = c + 0.42 * float2(cos(a), sin(a));
        d = min(d, sdSegment(p, float3(prev, 0), float3(next, 0), 0.07));
        prev = next;
    }
    d = min(d, sdSegment(p, float3(0, -0.17, 0), float3(0, -0.72, 0), 0.07));          // stem
    d = min(d, sdSegment(p, float3(-0.36, -0.78, 0), float3(0.36, -0.78, 0), 0.07));   // foot
    float3 q = p - float3(0, 0.12, 0);                                                  // the wine
    q.xy = q.xy * rot(0.28 * sin(t * 2.0));
    d = min(d, sdSegment(q, float3(-0.36, 0, 0), float3(0.36, 0, 0), 0.09));
    return d;
}

ORB_FORMA(bicchiere_vino)
