#include "../OrbShading.h"

// Agente: a half-closed eye with lashes; the lids shut and open again in a blink now and then.
static float occhio(float3 p, float t) {
    float open = 1.0 - pulse(fract(t / 3.2), 0.5, 0.04);
    const float xs[5] = { -0.8, -0.4, 0.0, 0.4, 0.8 };
    const float k[5] = { 0.0, 0.75, 1.0, 0.75, 0.0 };
    float d = 9.0;
    float2 up[5], low[5];
    for (int i = 0; i < 5; i++) {
        up[i] = float2(xs[i], 0.30 * open * k[i]);
        low[i] = float2(xs[i], -0.22 * open * k[i]);
    }
    for (int i = 0; i < 4; i++) {
        d = min(d, sdSegment(p, float3(up[i], 0), float3(up[i + 1], 0), 0.05));
        d = min(d, sdSegment(p, float3(low[i], 0), float3(low[i + 1], 0), 0.05));
    }
    for (int i = 1; i < 4; i++) {
        d = min(d, sdSegment(p, float3(up[i], 0), float3(up[i] + float2(xs[i] * 0.18, 0.2), 0), 0.03));
    }
    float iris = extrude(length(p.xy) - 0.2 * open, p.z, 0.03) - 0.04;
    return min(d, iris);
}

ORB_FORMA(occhio)
