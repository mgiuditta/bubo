#include "../OrbShading.h"

// The 2D half disc of radius r above y = 0, its flat side down.
static float ombrelloneCanopy(float2 p, float r) {
    if (p.y >= 0.0) return max(length(p) - r, -p.y);
    return length(float2(p.x - clamp(p.x, -r, r), p.y));
}

// Viaggi · mare: a beach umbrella planted at a slant, a half-disc canopy on a pole.
static float ombrellone(float3 p, float) {
    p.xy = p.xy * rot(0.3);
    float canopy = extrude(ombrelloneCanopy(p.xy - float2(0, 0.05), 0.80), p.z, 0.05) - 0.04;
    float pole = sdSegment(p, float3(0, 0.05, 0), float3(0, -0.95, 0), 0.045);
    float finial = length(p - float3(0, 0.92, 0)) - 0.07;
    return min(min(canopy, pole), finial);
}

ORB_FORMA(ombrellone)
