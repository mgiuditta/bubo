#include "../OrbShading.h"

// A 2D capsule along +y from the origin (radius r1) to (0, h) (radius r2).
static float piumaCapsule(float2 p, float r1, float r2, float h) {
    p.x = abs(p.x);
    float b = (r1 - r2) / h, a = sqrt(1.0 - b * b);
    float k = dot(p, float2(-b, a));
    if (k < 0.0) return length(p) - r1;
    if (k > a * h) return length(p - float2(0, h)) - r2;
    return dot(p, float2(a, b)) - r1;
}

// Creativo · poesia: a quill leaning to the right, vane widest at the middle and a bare shaft at the foot; it sways.
static float piuma(float3 p, float t) {
    float a = 0.6 + 0.08 * sin(t * 1.4);
    float2 l = p.xy * rot(a) + float2(0, 0.425);
    float vane = min(piumaCapsule(l, 0.03, 0.24, 0.70), piumaCapsule(l - float2(0, 0.70), 0.24, 0.02, 0.60));
    float body = extrude(vane, p.z, 0.025) - 0.02;
    float shaft = sdSegment(float3(l, p.z), float3(0, -0.45, 0.02), float3(0, 1.28, 0.02), 0.03);
    return min(body, shaft);
}

ORB_FORMA(piuma)
