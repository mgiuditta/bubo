#include "../OrbShading.h"

// Agente: a ball of yarn wound with three bands and a loose thread that unrolls a little, then winds back.
static float gomitolo(float3 p, float t) {
    float3 q = p - float3(-0.3, 0.15, 0);
    float d = length(q) - 0.48;
    d = min(d, sdTorusXY(q, 0.50, 0.035));
    float3 a = q;
    a.xz = a.xz * rot(1.05);
    d = min(d, sdTorusXY(a, 0.50, 0.035));
    float3 b = q;
    b.xz = b.xz * rot(-1.05);
    d = min(d, sdTorusXY(b, 0.50, 0.035));
    float u = 0.5 + 0.5 * sin(t * 0.9);
    float2 tail[4] = { float2(0.07, -0.15), float2(0.30, -0.55), float2(0.55, -0.62), float2(0.70 + 0.12 * u, -0.72) };
    for (int i = 0; i < 3; i++) {
        d = min(d, sdSegment(p, float3(tail[i], 0), float3(tail[i + 1], 0), 0.035));
    }
    return d;
}

ORB_FORMA(gomitolo)
