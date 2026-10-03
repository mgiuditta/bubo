#include "../OrbShading.h"

// Agente · hook: a hook hung from an eyelet, a shank, a half circle for the bend and a pointed tip; it swings a little.
static float uncino(float3 p, float t) {
    const float s = 1.25;
    float3 q = p / s;
    const float2 eye = float2(-0.30, 0.60);
    q.xy = (q.xy - eye) * rot(0.12 * sin(t * 1.5)) + eye;
    float d = min(sdTorusXY(q - float3(eye, 0), 0.10, 0.04), sdSegment(q, float3(-0.30, 0.50, 0), float3(-0.30, -0.10, 0), 0.06));
    float2 prev = float2(-0.30, -0.10);
    for (int i = 1; i <= 8; i++) {
        float a = 3.1415927 + 3.1415927 * float(i) / 8.0;
        float2 next = 0.30 * float2(cos(a), sin(a)) + float2(0, -0.10);
        d = min(d, sdSegment(q, float3(prev, 0), float3(next, 0), 0.06));
        prev = next;
    }
    d = min(d, sdRoundCone(q, float3(0.30, -0.10, 0), float3(0.30, 0.15, 0), 0.06, 0.02));
    return d * s;
}

ORB_FORMA(uncino)
