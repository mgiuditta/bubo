#include "../OrbShading.h"

// Mail · phishing: a fishing hook with its eye, swinging from the eye like a pendulum.
static float amo(float3 p, float t) {
    const float2 pivot = float2(0.15, 0.72);
    float2 c = p.xy - float2(0.15, -0.13) - pivot;
    c = c * rot(0.25 * sin(t * 1.5)) + pivot;
    float eye = abs(length(c - pivot) - 0.13) - 0.035;
    float line = min(udSegment2(c, float2(0.15, 0.59), float2(0.15, -0.25)),
                     min(udSegment2(c, float2(-0.45, -0.25), float2(-0.45, 0.05)),
                         udSegment2(c, float2(-0.45, 0.05), float2(-0.33, -0.07)))) - 0.035;
    float bend = min(udQuarterArc(c, float2(-0.15, -0.25), 0.30, float2(1, -1)),
                     udQuarterArc(c, float2(-0.15, -0.25), 0.30, float2(-1, -1))) - 0.035;
    return extrude(min(eye, min(line, bend)), p.z, 0.03) - 0.02;
}

ORB_FORMA(amo)
