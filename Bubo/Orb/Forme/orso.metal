#include "../OrbShading.h"

// Finanza · mercati in ribasso: a bear in profile facing right, head low, four-square on two legs.
static float orso(float3 p, float) {
    float body = sdRoundCone(p, float3(-0.35, 0.0, 0), float3(0.2, 0.05, 0), 0.42, 0.38);
    float hump = length(p - float3(0, 0.2, 0)) - 0.38;
    float head = length(p - float3(0.58, -0.1, 0)) - 0.26;
    float snout = sdRoundCone(p, float3(0.72, -0.18, 0), float3(0.9, -0.26, 0), 0.14, 0.09);
    float ear = length(p - float3(0.5, 0.14, 0.12)) - 0.09;
    float legs = min(sdRoundCone(p, float3(-0.5, -0.3, 0), float3(-0.5, -0.85, 0), 0.17, 0.13),
                     sdRoundCone(p, float3(0.25, -0.3, 0), float3(0.25, -0.85, 0), 0.17, 0.13));
    float tail = length(p - float3(-0.8, 0.1, 0)) - 0.1;
    return min(min(min(body, hump), min(head, snout)), min(min(ear, legs), tail));
}

ORB_FORMA(orso)
