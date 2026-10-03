#include "../OrbShading.h"

// One leg on `side` (±1): hip, knee and foot, swung by `swing` radians around the hip.
static float ragnoLeg(float3 p, float side, float2 hip, float2 knee, float2 foot, float swing) {
    float2x2 r = rot(swing * side);
    float2 h = float2(hip.x * side, hip.y);
    float2 k = h + float2((knee.x - hip.x) * side, knee.y - hip.y) * r;
    float2 f = k + float2((foot.x - knee.x) * side, foot.y - knee.y) * r;
    return min(sdSegment(p, float3(h, 0), float3(k, 0), 0.04), sdSegment(p, float3(k, 0), float3(f, 0), 0.035));
}

// Chat · natura: a spider from above, round abdomen and eight bent legs that step in turn.
static float ragno(float3 p, float t) {
    float d = min(length(p - float3(0, -0.22, 0)) - 0.28, length(p - float3(0, 0.2, 0)) - 0.18);
    const float2 hips[4] = { float2(0.1, 0.24), float2(0.12, 0.14), float2(0.12, 0.04), float2(0.1, -0.06) };
    const float2 knees[4] = { float2(0.35, 0.5), float2(0.45, 0.28), float2(0.45, -0.12), float2(0.35, -0.45) };
    const float2 feet[4] = { float2(0.62, 0.55), float2(0.75, 0.18), float2(0.75, -0.2), float2(0.6, -0.7) };
    for (int i = 0; i < 4; i++) {
        for (int s = 0; s < 2; s++) {
            float side = s == 0 ? -1.0 : 1.0;
            float swing = 0.12 * sin(t * 3.0 + M_PI_F * float((i + s) % 2));
            d = min(d, ragnoLeg(p, side, hips[i], knees[i], feet[i], swing));
        }
    }
    return d;
}

ORB_FORMA(ragno)
