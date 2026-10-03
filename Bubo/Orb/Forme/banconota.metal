#include "../OrbShading.h"

// Finanza: a banknote, slightly turned, with a framed border, a round seal at the centre and corner discs.
static float banconota(float3 p, float) {
    p.xy = p.xy * rot(0.12);
    float3 q = float3(abs(p.x), abs(p.y), p.z);
    float note = sdRoundBox(p, float3(0.85, 0.45, 0.04), 0.03);
    float frame = extrude(abs(sdRoundBox2(p.xy, float2(0.72, 0.33), 0.05)) - 0.018, p.z - 0.07, 0.01);
    float seal = extrude(length(p.xy) - 0.19, p.z - 0.07, 0.025) - 0.01;
    float corner = extrude(length(q.xy - float2(0.52, 0.2)) - 0.07, p.z - 0.07, 0.025) - 0.01;
    return min(min(note, frame), min(seal, corner));
}

ORB_FORMA(banconota)
