#include "../OrbShading.h"

// Salute · corpo: a mosquito in profile facing right, long proboscis and legs; the wings buzz.
static float zanzara(float3 p, float t) {
    p.x += 0.1;
    p.y -= 0.07;
    float thorax = length(p - float3(0, 0.05, 0)) - 0.15;
    float head = length(p - float3(0.17, 0.1, 0)) - 0.09;
    float abdomen = sdSegment(p, float3(-0.05, 0.0, 0), float3(-0.45, -0.15, 0), 0.09);
    float proboscis = sdSegment(p, float3(0.22, 0.08, 0), float3(0.7, -0.2, 0), 0.025);
    float legs = min(min(sdSegment(p, float3(-0.04, -0.05, 0), float3(-0.3, -0.5, 0), 0.03),
                         sdSegment(p, float3(-0.3, -0.5, 0), float3(-0.42, -0.85, 0), 0.025)),
                     min(min(sdSegment(p, float3(0.0, -0.06, 0), float3(0.0, -0.5, 0), 0.03),
                             sdSegment(p, float3(0.0, -0.5, 0), float3(-0.05, -0.85, 0), 0.025)),
                         min(sdSegment(p, float3(0.05, -0.05, 0), float3(0.28, -0.45, 0), 0.03),
                             sdSegment(p, float3(0.28, -0.45, 0), float3(0.4, -0.8, 0), 0.025))));
    float buzz = 0.12 * sin(t * 14.0);
    float3 w = p - float3(-0.02, 0.12, 0);
    float2 w1 = w.xy * rot(buzz), w2 = w.xy * rot(-buzz);
    float wings = min(sdSegment(float3(w1, w.z), float3(0), float3(-0.3, 0.53, 0), 0.06),
                      sdSegment(float3(w2, w.z), float3(0.03, 0.0, 0.08), float3(-0.12, 0.56, 0.08), 0.05));
    return min(min(min(thorax, head), min(abdomen, proboscis)), min(legs, wings));
}

ORB_FORMA(zanzara)
