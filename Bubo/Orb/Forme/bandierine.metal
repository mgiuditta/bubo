#include "../OrbShading.h"

// Codice · scrittura: a string of five triangular pennants hung from a sagging line; the whole garland sways a little.
static float bandierine(float3 p, float t) {
    const float2 pivot = float2(0, 0.4);
    float3 q = p;
    q.xy = pivot + (p.xy - pivot) * rot(0.06 * sin(t * 1.2));
    float d = 9.0;
    for (int i = 0; i < 8; i++) {
        float xa = -0.85 + 0.2125 * float(i), xb = xa + 0.2125;
        float2 a = float2(xa, -0.05 + 0.45 * (xa / 0.85) * (xa / 0.85));
        float2 b = float2(xb, -0.05 + 0.45 * (xb / 0.85) * (xb / 0.85));
        d = min(d, sdSegment(q, float3(a, 0), float3(b, 0), 0.03));
    }
    float2 f = float2(0);
    float flags = 9.0;
    for (int i = 0; i < 5; i++) {
        float x = -0.6 + 0.3 * float(i);
        float y = -0.05 + 0.45 * (x / 0.85) * (x / 0.85);
        flags = min(flags, sdQuad2(q.xy, float2(x - 0.11, y), float2(x, y), float2(x + 0.11, y), float2(x, y - 0.34)));
    }
    return min(d, extrude(flags, q.z, 0.025) - 0.015);
}

ORB_FORMA(bandierine)
