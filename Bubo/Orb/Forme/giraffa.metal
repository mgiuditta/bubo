#include "../OrbShading.h"

// Chat · natura: a giraffe in profile facing right, long neck, little horns, four thin legs.
static float giraffa(float3 p, float) {
    p.y -= 0.02;
    float body = sdSegment(p, float3(-0.34, -0.12, 0), float3(0.04, -0.12, 0), 0.17);
    float neck = sdSegment(p, float3(0.0, -0.05, 0), float3(0.3, 0.58, 0), 0.075);
    float head = sdRoundCone(p, float3(0.3, 0.6, 0), float3(0.52, 0.54, 0), 0.1, 0.06);
    float horns = min(sdSegment(p, float3(0.27, 0.68, 0), float3(0.25, 0.82, 0), 0.03),
                      sdSegment(p, float3(0.34, 0.68, 0), float3(0.36, 0.82, 0), 0.03));
    float legs = min(min(sdSegment(p, float3(-0.34, -0.2, 0), float3(-0.36, -0.82, 0), 0.04),
                         sdSegment(p, float3(-0.22, -0.2, 0), float3(-0.22, -0.82, 0), 0.04)),
                     min(sdSegment(p, float3(-0.02, -0.2, 0), float3(0.0, -0.82, 0), 0.04),
                         sdSegment(p, float3(0.1, -0.2, 0), float3(0.12, -0.82, 0), 0.04)));
    float tail = sdSegment(p, float3(-0.5, -0.1, 0), float3(-0.56, -0.38, 0), 0.025);
    return min(min(min(body, neck), min(head, horns)), min(legs, tail));
}

ORB_FORMA(giraffa)
