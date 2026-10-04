#include "../OrbShading.h"

// Creativo: a film projector in profile, two reels on top and its lens throwing a cone of light.
static float proiettore(float3 p, float) {
    p /= 0.92;
    p.y -= 0.2;
    float body = sdRoundBox(p - float3(-0.5, -0.2, 0), float3(0.4, 0.25, 0.18), 0.08);
    float lens = sdCylinder((p - float3(0.0, -0.2, 0)).yxz, 0.13, 0.1);
    float reel1 = extrude(length(p.xy - float2(-0.7, 0.22)) - 0.14, p.z, 0.05) - 0.04;
    float reel2 = extrude(length(p.xy - float2(-0.3, 0.22)) - 0.14, p.z, 0.05) - 0.04;
    const float r = 0.04;
    float ray1 = sdSegment(p, float3(0.1, -0.07, 0), float3(0.95, 0.45, 0), r);
    float ray2 = sdSegment(p, float3(0.1, -0.33, 0), float3(0.95, -0.85, 0), r);
    float edge = sdSegment(p, float3(0.95, 0.45, 0), float3(0.95, -0.85, 0), r);
    float foot = min(sdSegment(p, float3(-0.8, -0.45, 0), float3(-0.85, -0.65, 0), 0.05),
                     sdSegment(p, float3(-0.2, -0.45, 0), float3(-0.15, -0.65, 0), 0.05));
    return min(min(min(body, lens), min(reel1, reel2)), min(min(ray1, ray2), min(edge, foot))) * 0.92;
}

ORB_FORMA(proiettore)
