#include "../OrbShading.h"

// Salute · infortuni e riabilitazione: a crutch, two uprights with the padded arm rest on top, a grip and rubber tips.
static float stampella(float3 p, float) {
    float left = sdSegment(p, float3(-0.3, 0.8, 0), float3(-0.1, -0.9, 0), 0.05);
    float right = sdSegment(p, float3(0.02, 0.8, 0), float3(0.22, -0.9, 0), 0.05);
    float pad = sdSegment(p, float3(-0.5, 0.84, 0), float3(0.26, 0.88, 0), 0.1);
    float grip = sdSegment(p, float3(-0.215, 0.0, 0), float3(0.115, 0.0, 0), 0.07);
    float tips = min(length(p - float3(-0.1, -0.93, 0)) - 0.08, length(p - float3(0.22, -0.93, 0)) - 0.08);
    float brace = sdSegment(p, float3(-0.16, -0.5, 0), float3(0.17, -0.5, 0), 0.03);
    return min(min(min(left, right), min(pad, grip)), min(tips, brace));
}

ORB_FORMA(stampella)
