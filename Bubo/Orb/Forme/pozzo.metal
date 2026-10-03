#include "../OrbShading.h"

// Ricerca: a stone well with a gabled roof, a beam and a bucket on its rope; the bucket goes up and down.
static float pozzo(float3 p, float t) {
    float body = sdCylinder(p - float3(0, -0.45, 0), 0.55, 0.3);
    float posts = min(sdSegment(p, float3(-0.5, -0.15, 0), float3(-0.5, 0.5, 0), 0.05), sdSegment(p, float3(0.5, -0.15, 0), float3(0.5, 0.5, 0), 0.05));
    float roof = extrude(sdQuad2(p.xy, float2(-0.68, 0.5), float2(0.68, 0.5), float2(0.06, 0.88), float2(-0.06, 0.88)), p.z, 0.21) - 0.04;
    float beam = sdSegment(p, float3(-0.5, 0.2, 0), float3(0.5, 0.2, 0), 0.04);
    float yb = 0.2 * sin(t * 1.2);
    float rope = sdSegment(p, float3(0, 0.2, 0), float3(0, yb + 0.1, 0), 0.02);
    float bucket = sdCappedCone(p - float3(0, yb, 0), 0.1, 0.1, 0.13);
    return min(min(body, posts), min(roof, min(beam, min(rope, bucket))));
}

ORB_FORMA(pozzo)
