#include "../OrbShading.h"

// One leg on `side` (±1): hip, knee and foot, swung by `swing` radians around the hip.
static float insettoLeg(float3 p, float side, float2 hip, float2 knee, float2 foot, float swing) {
    float2x2 r = rot(swing * side);
    float2 h = float2(hip.x * side, hip.y);
    float2 k = h + float2(knee.x * side, knee.y) * r;
    float2 f = k + float2(foot.x * side, foot.y) * r;
    return min(sdSegment(p, float3(h, 0), float3(k, 0), 0.04), sdSegment(p, float3(k, 0), float3(f, 0), 0.035));
}

// Codice · verifica: a round beetle seen from above, six legs and two antennae; the legs step in two tripods.
static float insetto(float3 p, float t) {
    float body = extrude(length(p.xy - float2(0, -0.10)) - 0.30, p.z, 0.06) - 0.15;
    float head = extrude(length(p.xy - float2(0, 0.43)) - 0.08, p.z, 0.04) - 0.10;
    float seam = sdSegment(p, float3(0, 0.28, 0.19), float3(0, -0.50, 0.19), 0.03);
    float3 q = float3(abs(p.x), p.y, p.z);
    float antenna = min(sdSegment(q, float3(0.07, 0.55, 0), float3(0.24, 0.86, 0), 0.03),
                        length(q - float3(0.24, 0.86, 0)) - 0.05);
    float d = min(min(body, head), min(seam, antenna));
    const float2 hips[3] = { float2(0.28, 0.12), float2(0.32, -0.10), float2(0.28, -0.32) };
    const float2 knees[3] = { float2(0.26, 0.16), float2(0.30, 0.0), float2(0.26, -0.16) };
    const float2 feet[3] = { float2(0.06, 0.16), float2(0.14, -0.06), float2(0.06, -0.16) };
    for (int i = 0; i < 3; i++) {
        for (int s = 0; s < 2; s++) {
            float side = s == 0 ? -1.0 : 1.0;
            float swing = 0.22 * sin(t * 3.0 + M_PI_F * float((i + s) % 2)); // tripods in turn
            d = min(d, insettoLeg(p, side, hips[i], knees[i], feet[i], swing));
        }
    }
    return d;
}

ORB_FORMA(insetto)
