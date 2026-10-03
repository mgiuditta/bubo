#include "../OrbShading.h"

// Tempo: an egg-shaped kitchen timer with a graduated dial; the pointer winds back notch by notch.
static float contaminuti(float3 p, float t) {
    float egg = sdRoundCone(p, float3(0, -0.38, 0), float3(0, 0.35, 0), 0.55, 0.38);
    float knob = sdCylinder(p - float3(0, 0.76, 0), 0.1, 0.05);
    float3 q = p - float3(0, -0.05, 0.36);
    float ring = sdTorusXY(q, 0.3, 0.045);
    float x = t / 1.2;
    float a = -(floor(x) + smoothstep(0.8, 1.0, fract(x))) * M_PI_F / 6.0;
    float2 tip = 0.3 * float2(sin(a), cos(a));
    float hand = sdSegment(q, float3(0, 0, 0.04), float3(tip, 0.04), 0.05);
    float ticks = 9.0;
    for (int i = 0; i < 12; i++) {
        float ta = float(i) * M_PI_F / 6.0;
        ticks = min(ticks, length(q - float3(0.3 * sin(ta), 0.3 * cos(ta), 0.02)) - 0.07);
    }
    return min(min(egg, knob), min(min(ring, hand), ticks));
}

ORB_FORMA(contaminuti)
