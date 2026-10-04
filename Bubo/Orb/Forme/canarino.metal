#include "../OrbShading.h"

// Codice · rilascio graduale: a canary in profile on its perch, facing right; it tilts its head now and then.
static float canarino(float3 p, float t) {
    float body = sdRoundCone(p, float3(-0.25, -0.15, 0), float3(0.15, 0.15, 0), 0.30, 0.38);
    float tail = sdRoundCone(p, float3(-0.35, -0.25, 0), float3(-0.85, -0.55, 0), 0.12, 0.06);
    float perch = sdSegment(p, float3(-0.85, -0.65, 0), float3(0.85, -0.65, 0), 0.06);
    float legs = min(sdSegment(p, float3(-0.05, -0.40, 0), float3(-0.05, -0.62, 0), 0.04),
                     sdSegment(p, float3(0.12, -0.40, 0), float3(0.12, -0.62, 0), 0.04));
    const float2 neck = float2(0.15, 0.30);
    float3 q = p;
    q.xy = (p.xy - neck) * rot(0.2 * sin(t * 1.5)) + neck;
    float head = length(q - float3(0.28, 0.42, 0)) - 0.25;
    float beak = sdRoundCone(q, float3(0.46, 0.44, 0), float3(0.68, 0.38, 0), 0.08, 0.02);
    float eye = length(q - float3(0.34, 0.5, 0.22)) - 0.04;
    return min(min(min(body, tail), min(perch, legs)), min(min(head, beak), eye));
}

ORB_FORMA(canarino)
