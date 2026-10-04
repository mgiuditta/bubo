#include "../OrbShading.h"

// Salute · corpo: a virus, a sphere with twelve spikes ending in round pads; it turns slowly.
static float virus(float3 p, float t) {
    p.xz = p.xz * rot(t * 0.4);
    float d = length(p) - 0.45;
    const float3 v[6] = { float3(0, 0.5257, 0.8507), float3(0, 0.5257, -0.8507), float3(0.5257, 0.8507, 0),
                          float3(-0.5257, 0.8507, 0), float3(0.8507, 0, 0.5257), float3(0.8507, 0, -0.5257) };
    for (int i = 0; i < 6; i++) {
        d = min(d, min(sdSegment(p, v[i] * 0.4, v[i] * 0.62, 0.04), sdSegment(p, -v[i] * 0.4, -v[i] * 0.62, 0.04)));
        d = min(d, min(length(p - v[i] * 0.68), length(p + v[i] * 0.68)) - 0.1);
    }
    return d;
}

ORB_FORMA(virus)
