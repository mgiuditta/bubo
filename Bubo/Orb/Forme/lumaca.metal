#include "../OrbShading.h"

// Codice · verifica: a snail in profile, spiral shell and two eye stalks, crawling forward and back.
static float lumaca(float3 p, float t) {
    p.x -= 0.12 * sin(t * 0.9);
    float shell = extrude(length(p.xy - float2(-0.10, 0.05)) - 0.48, p.z, 0.10);
    float ridge = sdTorusXY(p - float3(-0.10, 0.05, 0.10), 0.30, 0.045);
    float ridgeIn = sdTorusXY(p - float3(-0.10, 0.05, 0.10), 0.13, 0.04);
    float foot = sdSegment(p, float3(-0.72, -0.45, 0), float3(0.55, -0.45, 0), 0.12);
    float neck = sdSegment(p, float3(0.45, -0.45, 0), float3(0.62, -0.02, 0), 0.10);
    float head = length(p - float3(0.65, 0.0, 0)) - 0.12;
    float stalks = min(sdSegment(p, float3(0.62, 0.05, 0), float3(0.58, 0.36, 0), 0.03),
                       sdSegment(p, float3(0.68, 0.05, 0), float3(0.82, 0.34, 0), 0.03));
    float eyes = min(length(p - float3(0.58, 0.38, 0)) - 0.06, length(p - float3(0.82, 0.36, 0)) - 0.06);
    return min(min(min(shell, ridge), min(ridgeIn, foot)), min(min(neck, head), min(stalks, eyes)));
}

ORB_FORMA(lumaca)
