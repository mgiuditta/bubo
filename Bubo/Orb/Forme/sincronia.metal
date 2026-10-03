#include "../OrbShading.h"

// Codice · rilascio: two curved arrows chasing each other in a circle, turning slowly.
static float sincronia(float3 p, float t) {
    p.xy = p.xy * rot(-t * 0.5);
    const float radius = 0.55;
    float d = 9.0;
    for (int k = 0; k < 2; k++) {
        float a0 = float(k) * M_PI_F + 0.35, a1 = a0 + 2.1;
        float2 prev = radius * float2(cos(a0), sin(a0));
        for (int i = 1; i <= 8; i++) {
            float a = a0 + (a1 - a0) * float(i) / 8.0;
            float2 next = radius * float2(cos(a), sin(a));
            d = min(d, sdSegment(p, float3(prev, 0), float3(next, 0), 0.08));
            prev = next;
        }
        float2 n = float2(cos(a1), sin(a1)), tg = float2(-n.y, n.x);
        float2 tip = radius * n + tg * 0.2, back = radius * n - tg * 0.1;
        d = min(d, extrude(sdQuad2(p.xy, tip, back + n * 0.22, back + tg * 0.12, back - n * 0.22), p.z, 0.05) - 0.03);
    }
    return d;
}

ORB_FORMA(sincronia)
