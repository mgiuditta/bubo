#include "../OrbShading.h"

// Tempo · fretta: a hare running in profile, facing right, long ears laid back; it hops forward.
static float lepre(float3 p, float t) {
    float3 q = p - float3(0, 0.12 * abs(sin(t * 2.0)), 0);
    float body = sdRoundCone(q, float3(-0.3, -0.1, 0), float3(0.2, 0.1, 0), 0.30, 0.25);
    float haunch = length(q - float3(-0.35, -0.15, 0)) - 0.35;
    float head = length(q - float3(0.45, 0.3, 0)) - 0.17;
    float snout = sdRoundCone(q, float3(0.58, 0.28, 0), float3(0.78, 0.2, 0), 0.10, 0.04);
    float ears = min(sdRoundCone(q, float3(0.38, 0.42, 0), float3(0.1, 0.85, 0), 0.06, 0.03),
                     sdRoundCone(q, float3(0.45, 0.45, 0), float3(0.3, 0.9, 0), 0.06, 0.03));
    float legs = min(sdRoundCone(q, float3(-0.4, -0.3, 0), float3(-0.85, -0.55, 0), 0.12, 0.06),
                     sdRoundCone(q, float3(0.2, -0.1, 0), float3(0.6, -0.45, 0), 0.08, 0.04));
    float tail = length(q - float3(-0.65, 0.05, 0)) - 0.1;
    return min(min(min(body, haunch), min(head, snout)), min(min(ears, legs), tail));
}

ORB_FORMA(lepre)
