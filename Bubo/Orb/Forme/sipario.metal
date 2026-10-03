#include "../OrbShading.h"

// Creativo: a stage curtain: two drapes gathered toward the sides under a valance, swaying open and shut a little.
static float sipario(float3 p, float t) {
    float w = 0.07 * sin(t * 1.4);
    float2 q = float2(abs(p.x), p.y);                  // the drapes are mirror images
    float drape = sdQuad2(q, float2(0.85, 0.68), float2(0.08, 0.68), float2(0.35 + w, -0.20), float2(0.85, -0.80));
    float d = extrude(drape, p.z, 0.08) - 0.02;
    float3 s = float3(q, p.z);
    float folds = min(min(sdSegment(s, float3(0.30, 0.64, 0.10), float3(0.42 + w, -0.15, 0.10), 0.03),
                          sdSegment(s, float3(0.50, 0.64, 0.10), float3(0.62 + w, -0.40, 0.10), 0.03)),
                      sdSegment(s, float3(0.70, 0.64, 0.10), float3(0.78 + w, -0.60, 0.10), 0.03));
    float valance = sdRoundBox(p - float3(0, 0.76, 0), float3(0.86, 0.09, 0.13), 0.04);
    return min(min(d, folds), valance);
}

ORB_FORMA(sipario)
