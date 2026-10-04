#include "../OrbShading.h"

// Meteo · afa: a hand fan, a wide wedge with ribs and a handle; it opens and closes a little.
static float ventaglio(float3 p, float t) {
    const float2 pivot = float2(0, -0.55);
    float a = 1.15 + 0.12 * sin(t * 0.9);
    float2 c = float2(sin(a), cos(a));
    float2 q = p.xy - pivot;
    q.x = abs(q.x);
    float l = length(q) - 1.0;
    float m = length(q - c * clamp(dot(q, c), 0.0, 1.0));
    float wedge = max(l, m * sign(c.y * q.x - c.x * q.y));
    float d = extrude(wedge, p.z, 0.04) - 0.03;
    d = min(d, sdSegment(p, float3(pivot, 0), float3(pivot.x, -0.92, 0), 0.06));
    for (int i = -2; i <= 2; i++) {
        float r = a * float(i) / 2.0;
        d = min(d, sdSegment(p, float3(pivot, 0.07), float3(pivot + 0.94 * float2(sin(r), cos(r)), 0.07), 0.025));
    }
    return d;
}

ORB_FORMA(ventaglio)
