#include "../OrbShading.h"

// Salute: an ice skate in profile, a tall boot with the toe to the right on a blade held by two struts.
static float pattino(float3 p, float) {
    float shaft = sdRoundBox(p - float3(-0.2, 0.2, 0), float3(0.3, 0.5, 0.25), 0.1);
    float foot = sdRoundBox(p - float3(0.05, -0.25, 0), float3(0.65, 0.22, 0.25), 0.12);
    float blade = min(sdSegment(p, float3(-0.7, -0.65, 0), float3(0.75, -0.65, 0), 0.05), sdSegment(p, float3(0.75, -0.65, 0), float3(0.88, -0.5, 0), 0.05));
    float struts = min(sdSegment(p, float3(-0.5, -0.4, 0), float3(-0.5, -0.62, 0), 0.04), sdSegment(p, float3(0.5, -0.4, 0), float3(0.5, -0.62, 0), 0.04));
    return min(min(shaft, foot), min(blade, struts));
}

ORB_FORMA(pattino)
