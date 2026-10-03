#include "../OrbShading.h"

// Chat · natura: a telescope tilted up on a tripod.
static float telescopio(float3 p, float) {
    float3 q = p - float3(0, 0.28, 0);
    q.xy = q.xy * rot(-0.45);
    float tube = sdCylinder((q - float3(0.05, 0, 0)).yxz, 0.17, 0.5);
    float bell = sdCappedCone((q - float3(0.62, 0, 0)).yxz, 0.12, 0.17, 0.24);
    float eye = sdCylinder((q - float3(-0.62, 0, 0)).yxz, 0.09, 0.12);
    float head = length(p - float3(0, 0.05, 0)) - 0.1;
    const float3 top = float3(0, 0.05, 0);
    float legs = min(sdSegment(p, top, float3(-0.5, -0.85, 0.1), 0.04),
                     min(sdSegment(p, top, float3(0.5, -0.85, 0.1), 0.04), sdSegment(p, top, float3(0, -0.85, -0.25), 0.04)));
    return min(min(tube, bell), min(eye, min(head, legs)));
}

ORB_FORMA(telescopio)
