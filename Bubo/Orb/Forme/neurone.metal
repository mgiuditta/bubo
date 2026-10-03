#include "../OrbShading.h"

// A branch that forks: from a to the fork m, then to the tips e1 and e2.
static float neuroneBranch(float3 p, float2 a, float2 m, float2 e1, float2 e2) {
    const float r = 0.05;
    return min(sdSegment(p, float3(a, 0), float3(m, 0), r),
               min(sdSegment(p, float3(m, 0), float3(e1, 0), r), sdSegment(p, float3(m, 0), float3(e2, 0), r)));
}

// Codice · scrittura: a neuron, a round body with four branching dendrites and a long axon; an impulse runs along the axon.
static float neurone(float3 p, float t) {
    float d = length(p - float3(-0.4, 0, 0)) - 0.3;
    d = min(d, neuroneBranch(p, float2(-0.4, 0.2), float2(-0.5, 0.55), float2(-0.75, 0.8), float2(-0.4, 0.85)));
    d = min(d, neuroneBranch(p, float2(-0.6, 0.1), float2(-0.85, 0.25), float2(-0.95, 0.4), float2(-1.05, 0.1)));
    d = min(d, neuroneBranch(p, float2(-0.6, -0.1), float2(-0.85, -0.25), float2(-1.0, -0.4), float2(-1.05, -0.1)));
    d = min(d, neuroneBranch(p, float2(-0.4, -0.2), float2(-0.5, -0.55), float2(-0.75, -0.8), float2(-0.4, -0.85)));
    d = min(d, sdSegment(p, float3(-0.15, 0, 0), float3(0.55, 0, 0), 0.05));
    d = min(d, neuroneBranch(p, float2(0.55, 0), float2(0.8, 0.25), float2(0.95, 0.3), float2(0.95, 0.05)));
    d = min(d, neuroneBranch(p, float2(0.55, 0), float2(0.8, -0.25), float2(0.95, -0.3), float2(0.95, -0.05)));
    float x = -0.1 + 0.9 * fract(t / 2.0);
    return min(d, length(p - float3(x, 0, 0)) - 0.1);
}

ORB_FORMA(neurone)
