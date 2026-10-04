#include "../OrbShading.h"

// Chat: a cat sitting in profile, round head with two ears, a front leg and a curled tail that sways.
static float gatto(float3 p, float t) {
    float body = sdRoundCone(p, float3(-0.15, -0.45, 0), float3(0.10, 0.15, 0), 0.38, 0.26);
    float head = length(p - float3(0.15, 0.45, 0)) - 0.27;
    float ears = min(sdRoundCone(p, float3(0.0, 0.62, 0), float3(-0.05, 0.88, 0), 0.10, 0.02),
                     sdRoundCone(p, float3(0.3, 0.62, 0), float3(0.35, 0.88, 0), 0.10, 0.02));
    float leg = sdSegment(p, float3(0.2, -0.1, 0), float3(0.22, -0.72, 0), 0.10);
    float s = 0.08 * sin(t * 2.0);
    float3 t1 = float3(-0.88, -0.5, 0), t2 = float3(-0.92 + s, 0, 0), t3 = float3(-0.78 + s * 1.6, 0.3, 0);
    float tail = min(sdSegment(p, float3(-0.5, -0.6, 0), t1, 0.07), min(sdSegment(p, t1, t2, 0.07), sdSegment(p, t2, t3, 0.07)));
    return min(min(body, head), min(ears, min(leg, tail)));
}

ORB_FORMA(gatto)
