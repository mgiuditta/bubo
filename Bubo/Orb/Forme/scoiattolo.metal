#include "../OrbShading.h"

// Chat · natura: a squirrel sitting, facing right, with a big S tail that sways.
static float scoiattolo(float3 p, float t) {
    p.x -= 0.2;
    float sway = 0.08 * sin(t * 2.0);
    float body = sdRoundCone(p, float3(-0.05, -0.5, 0), float3(0, 0, 0), 0.3, 0.22);
    float head = length(p - float3(0.05, 0.25, 0)) - 0.2;
    float snout = length(p - float3(0.2, 0.2, 0)) - 0.09;
    float ears = min(length(p - float3(0.0, 0.45, 0)) - 0.06, length(p - float3(0.14, 0.43, 0)) - 0.06);
    float tail = min(min(sdSegment(p, float3(-0.2, -0.5, 0), float3(-0.5, -0.3, 0), 0.15),
                         sdSegment(p, float3(-0.5, -0.3, 0), float3(-0.5 + sway * 0.5, 0.2, 0), 0.17)),
                     sdSegment(p, float3(-0.5 + sway * 0.5, 0.2, 0), float3(-0.35 + sway, 0.62, 0), 0.14));
    return min(min(body, head), min(min(snout, ears), tail));
}

ORB_FORMA(scoiattolo)
