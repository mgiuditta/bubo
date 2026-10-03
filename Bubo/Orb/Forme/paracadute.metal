#include "../OrbShading.h"

// Viaggi: an open parachute, a dome made of wedges, four lines and a rider; the whole thing swings.
static float paracadute(float3 p, float t) {
    float3 q = p - float3(0, 0.9, 0);
    q.xy = q.xy * rot(0.2 * sin(t * 1.3));
    q.y += 0.9;
    const float2 c = float2(0, 0.05);
    float dome = 9.0;
    for (int k = 0; k < 8; k++) {
        float a0 = float(k) * 0.3926991, a1 = float(k + 1) * 0.3926991;
        float2 v1 = c + 0.75 * float2(cos(a0), sin(a0)), v2 = c + 0.75 * float2(cos(a1), sin(a1));
        dome = min(dome, sdQuad2(q.xy, c, v1, v2, 0.5 * (v2 + c)));
    }
    float canopy = extrude(dome, q.z, 0.1) - 0.04;
    float3 hook = float3(0, -0.58, 0);
    float lines = min(min(sdSegment(q, float3(-0.72, 0.05, 0), hook, 0.03), sdSegment(q, float3(0.72, 0.05, 0), hook, 0.03)),
                      min(sdSegment(q, float3(-0.36, 0.05, 0), hook, 0.03), sdSegment(q, float3(0.36, 0.05, 0), hook, 0.03)));
    float rider = sdSegment(q, float3(0, -0.6, 0), float3(0, -0.85, 0), 0.09);
    return min(canopy, min(lines, rider));
}

ORB_FORMA(paracadute)
