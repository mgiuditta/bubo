#include "../OrbShading.h"

// Musica · tempo musicale: a pyramid metronome with its weighted rod swinging in front.
static float metronomo(float3 p, float t) {
    float body = extrude(sdQuad2(p.xy, float2(-0.45, -0.85), float2(0.45, -0.85), float2(0.2, 0.65), float2(-0.2, 0.65)), p.z, 0.16) - 0.04;
    float base = sdRoundBox(p - float3(0, -0.88, 0), float3(0.55, 0.07, 0.24), 0.04);
    const float2 pivot = float2(0, -0.55);
    float3 q = p;
    q.xy = (p.xy - pivot) * rot(0.5 * sin(t * 3.0)) + pivot;
    float rod = sdSegment(q, float3(0, -0.55, 0.2), float3(0, 0.95, 0.2), 0.04);
    float weight = sdRoundBox(q - float3(0, 0.35, 0.2), float3(0.1, 0.09, 0.06), 0.03);
    float nub = length(q - float3(0, -0.55, 0.2)) - 0.07;
    return min(min(body, base), min(rod, min(weight, nub)));
}

ORB_FORMA(metronomo)
