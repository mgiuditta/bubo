#include "../OrbShading.h"

// Codice · pulizia: a straw broom with a long handle; it sweeps to the right and to the left.
static float scopa(float3 p, float t) {
    const float2 pivot = float2(0, 0.6);
    float3 q = p;
    q.xy = (p.xy - pivot) * rot(0.3 * sin(t * 2.4)) + pivot;
    float handle = sdSegment(q, float3(0, 0.95, 0), float3(0, -0.1, 0), 0.05);
    float head = extrude(sdQuad2(q.xy, float2(-0.12, -0.1), float2(0.12, -0.1), float2(0.4, -0.9), float2(-0.4, -0.9)), q.z, 0.08) - 0.04;
    float band = sdSegment(q, float3(-0.2, -0.25, 0.1), float3(0.2, -0.25, 0.1), 0.045);
    return min(min(handle, head), band);
}

ORB_FORMA(scopa)
