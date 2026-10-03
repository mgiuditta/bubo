#include "../OrbShading.h"

// Meteo: a wave in profile drawn in tube, its crest curling over; the curl closes and opens again.
static float onda(float3 p, float t) {
    const float2 curled[9] = { float2(-0.95, -0.35), float2(-0.6, -0.3), float2(-0.25, -0.1), float2(0.05, 0.3), float2(0.35, 0.55),
                               float2(0.65, 0.45), float2(0.75, 0.15), float2(0.55, -0.05), float2(0.35, 0.1) };
    const float2 relaxed[9] = { float2(-0.95, -0.35), float2(-0.6, -0.3), float2(-0.25, -0.2), float2(0.05, -0.05), float2(0.35, 0.1),
                                float2(0.6, 0.15), float2(0.8, 0.1), float2(0.9, 0.0), float2(0.95, -0.12) };
    float k = 0.5 + 0.5 * cos(t * 1.2);                   // 1 at rest: curled
    float d = 9.0;
    float2 prev = mix(relaxed[0], curled[0], k);
    for (int i = 1; i < 9; i++) {
        float2 next = mix(relaxed[i], curled[i], k);
        d = min(d, sdSegment(p, float3(prev, 0), float3(next, 0), 0.09));
        prev = next;
    }
    float foam = length(p - float3(mix(0.95, 0.58, k), mix(0.1, 0.36, k), 0.0)) - 0.11;
    float sea1 = sdSegment(p, float3(-0.9, -0.62, 0), float3(-0.1, -0.62, 0), 0.08);
    float sea2 = sdSegment(p, float3(0.15, -0.78, 0), float3(0.85, -0.78, 0), 0.08);
    return min(min(d, foam), min(sea1, sea2));
}

ORB_FORMA(onda)
