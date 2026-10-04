#include "../OrbShading.h"

// Chat · natura: a stag in profile facing right, branching antlers and four slim legs.
static float cervo(float3 p, float) {
    const float s = 0.9;
    p /= s;
    float body = sdSegment(p, float3(-0.3, -0.14, 0), float3(0.14, -0.1, 0), 0.22);
    float neck = sdSegment(p, float3(0.14, 0.0, 0), float3(0.4, 0.34, 0), 0.1);
    float head = sdRoundCone(p, float3(0.4, 0.36, 0), float3(0.6, 0.26, 0), 0.1, 0.05);
    float antlers = min(min(sdSegment(p, float3(0.38, 0.44, 0), float3(0.26, 0.86, 0), 0.03),
                            sdSegment(p, float3(0.32, 0.62, 0), float3(0.52, 0.76, 0), 0.03)),
                        min(sdSegment(p, float3(0.28, 0.78, 0), float3(0.08, 0.92, 0), 0.03),
                            sdSegment(p, float3(0.34, 0.5, 0), float3(0.1, 0.62, 0), 0.03)));
    float legs = min(min(sdSegment(p, float3(-0.36, -0.2, 0), float3(-0.4, -0.86, 0), 0.05),
                         sdSegment(p, float3(-0.22, -0.2, 0), float3(-0.24, -0.86, 0), 0.05)),
                     min(sdSegment(p, float3(0.02, -0.2, 0), float3(0.04, -0.86, 0), 0.05),
                         sdSegment(p, float3(0.14, -0.2, 0), float3(0.18, -0.86, 0), 0.05)));
    float tail = length(p - float3(-0.52, -0.02, 0)) - 0.06;
    return min(min(min(body, neck), min(head, antlers)), min(legs, tail)) * s;
}

ORB_FORMA(cervo)
