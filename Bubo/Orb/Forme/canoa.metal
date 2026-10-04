#include "../OrbShading.h"

// Viaggi: a canoe with its paddle over two lines of water; the boat and the paddle rock on the water.
static float canoa(float3 p, float t) {
    const float2 pivot = float2(0, -0.45);
    float3 q = p;
    q.xy = pivot + (p.xy - pivot) * rot(0.1 * sin(t * 1.5));
    float hull = extrude(sdQuad2(q.xy, float2(-0.9, 0.15), float2(0.9, 0.15), float2(0.5, -0.2), float2(-0.5, -0.2)), q.z, 0.16) - 0.04;
    float handle = sdSegment(q, float3(-0.1, 0.7, 0.3), float3(0.4, -0.4, 0.3), 0.04);
    float blade = sdSegment(q, float3(0.4, -0.4, 0.3), float3(0.48, -0.58, 0.3), 0.1);
    float water = min(sdSegment(p, float3(-0.8, -0.45, 0), float3(0.8, -0.45, 0), 0.04),
                      sdSegment(p, float3(-0.5, -0.62, 0), float3(0.5, -0.62, 0), 0.04));
    return min(min(hull, handle), min(blade, water));
}

ORB_FORMA(canoa)
