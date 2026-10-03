#include "../OrbShading.h"

// The 2D regular octagon of apothem r.
static float stopOctagon(float2 p, float r) {
    const float3 k = float3(-0.9238795325, 0.3826834323, 0.4142135623);
    p = abs(p);
    p -= 2.0 * min(dot(float2(k.x, k.y), p), 0.0) * float2(k.x, k.y);
    p -= 2.0 * min(dot(float2(-k.x, k.y), p), 0.0) * float2(-k.x, k.y);
    p -= float2(clamp(p.x, -k.z * r, k.z * r), r);
    return length(p) * sign(p.y);
}

// Codice: an octagonal sign with a raised border on a short post.
static float stop(float3 p, float) {
    float2 q = p.xy - float2(0, 0.30);
    float plate = extrude(stopOctagon(q, 0.50), p.z, 0.04) - 0.02;
    float rim = extrude(abs(stopOctagon(q, 0.40)) - 0.02, p.z - 0.05, 0.015) - 0.01;
    float post = sdRoundBox(p - float3(0, -0.55, 0), float3(0.07, 0.37, 0.05), 0.02);
    return min(plate, min(rim, post));
}

ORB_FORMA(stop)
