#include "../OrbShading.h"

// Chat · natura: a turtle in profile facing right; the head slips into the shell and comes out again.
static float tartaruga(float3 p, float t) {
    p.x += 0.12;
    float peek = 0.5 + 0.5 * sin(t * 0.9);
    float shell = sdSegment(p, float3(-0.2, 0, 0), float3(0.2, 0, 0), 0.4);
    float rim = sdRoundBox(p - float3(0, -0.34, 0), float3(0.62, 0.05, 0.2), 0.05);
    float3 head = float3(0.5 + 0.3 * peek, 0.03 * peek, 0);
    float neck = sdSegment(p, float3(0.42, -0.02, 0), head, 0.09);
    float skull = length(p - head) - 0.13;
    float legs = min(sdSegment(p, float3(-0.36, -0.3, 0), float3(-0.4, -0.52, 0), 0.09),
                     sdSegment(p, float3(0.3, -0.3, 0), float3(0.33, -0.52, 0), 0.09));
    float tail = sdSegment(p, float3(-0.58, -0.15, 0), float3(-0.72, -0.2, 0), 0.04);
    return min(min(shell, rim), min(min(neck, skull), min(legs, tail)));
}

ORB_FORMA(tartaruga)
