#include "../OrbShading.h"

// Chat: a dog sitting in profile, with a snout and two upright ears, a front leg and a straight tail that wags.
static float cane(float3 p, float t) {
    float body = sdRoundCone(p, float3(-0.15, -0.45, 0), float3(0.10, 0.15, 0), 0.38, 0.26);
    float head = length(p - float3(0.2, 0.42, 0)) - 0.25;
    float snout = min(sdSegment(p, float3(0.4, 0.37, 0), float3(0.6, 0.31, 0), 0.11), length(p - float3(0.70, 0.32, 0)) - 0.05);
    float ears = min(sdRoundCone(p, float3(0.08, 0.58, 0), float3(0.02, 0.95, 0), 0.10, 0.03),
                     sdRoundCone(p, float3(0.3, 0.6, 0), float3(0.38, 0.92, 0), 0.10, 0.03));
    float leg = sdSegment(p, float3(0.22, -0.1, 0), float3(0.24, -0.72, 0), 0.10);
    float a = 0.8 + 0.5 * sin(t * 6.0);
    float3 root = float3(-0.45, -0.55, 0);
    float tail = sdSegment(p, root, root + 0.55 * float3(-cos(a), sin(a), 0), 0.07);
    return min(min(body, head), min(snout, min(ears, min(leg, tail))));
}

ORB_FORMA(cane)
