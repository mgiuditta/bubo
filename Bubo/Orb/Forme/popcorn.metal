#include "../OrbShading.h"

// Chat · cinema e film: a striped popcorn bucket heaped with popcorn; now and then one pops out and falls back.
static float popcorn(float3 p, float t) {
    p.y += 0.05;
    float bucket = sdCappedCone(p - float3(0, -0.5, 0), 0.38, 0.3, 0.46);
    float rim = sdCylinder(p - float3(0, -0.12, 0), 0.49, 0.04);
    const float3 heap[6] = { float3(-0.3, 0.0, 0.17), float3(0.0, 0.1, 0.2), float3(0.3, 0.0, 0.17), float3(-0.15, 0.25, 0.15), float3(0.17, 0.27, 0.14), float3(0.0, -0.04, 0.2) };
    float d = min(bucket, rim);
    for (int i = 0; i < 6; i++) d = min(d, length(p - float3(heap[i].xy, 0)) - heap[i].z);
    float ph = fract(t / 2.2 + 0.4);
    float3 k = float3(0.1 + 0.55 * (ph - 0.5), 0.3 + 1.5 * ph * (1.0 - ph), 0.05);
    float kern = min(length(p - k) - 0.13, length(p - k - float3(0.09, 0.07, 0)) - 0.09);
    return min(d, kern);
}

ORB_FORMA(popcorn)
