#include "../OrbShading.h"

// Chat · ambiente e rifiuti: three arrows chasing each other around a triangle; they turn slowly.
static float riciclo(float3 p, float t) {
    float2 turned = p.xy * rot(t * 0.5);
    float d = 9.0;
    for (int k = 0; k < 3; k++) {
        float3 w = float3(turned * rot(float(k) * 2.0943951), p.z);
        float shaft = sdSegment(w, float3(-0.1, 0.627, 0), float3(-0.475, -0.023, 0), 0.07);
        float head = sdRoundCone(w, float3(-0.475, -0.023, 0), float3(-0.625, -0.283, 0), 0.15, 0.02);
        d = min(d, min(shaft, head));
    }
    return d;
}

ORB_FORMA(riciclo)
