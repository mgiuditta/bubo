#include "../OrbShading.h"

// Salute · corpo: a capsule in two halves, tipped, with a band where they meet.
static float pillola(float3 p, float) {
    float3 q = p;
    q.xy = p.xy * rot(-0.7);
    float left = sdSegment(q, float3(-0.55, 0, 0), float3(0, 0, 0), 0.28);
    float right = sdSegment(q, float3(0, 0, 0), float3(0.55, 0, 0), 0.31);
    float band = sdCylinder(float3(q.y, q.x, q.z), 0.33, 0.025);
    return min(min(left, right), band);
}

ORB_FORMA(pillola)
