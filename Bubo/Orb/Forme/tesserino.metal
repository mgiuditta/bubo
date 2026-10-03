#include "../OrbShading.h"

// Agente: an ID badge on a lanyard, a rounded card with a clip, a photo, shoulders and two lines of text.
static float tesserino(float3 p, float) {
    float card = sdRoundBox(p - float3(0, -0.15, 0), float3(0.45, 0.62, 0.04), 0.07);
    float clip = sdRoundBox(p - float3(0, 0.5, 0), float3(0.14, 0.07, 0.06), 0.02);
    float lace = min(sdSegment(p, float3(-0.2, 0.47, 0), float3(0, 0.95, 0), 0.04), sdSegment(p, float3(0.2, 0.47, 0), float3(0, 0.95, 0), 0.04));
    float photo = extrude(length(p.xy - float2(0, 0.15)) - 0.2, p.z - 0.04, 0.03);
    float shoulders = extrude(sdRoundBox2(p.xy - float2(0, -0.15), float2(0.3, 0.1), 0.06), p.z - 0.04, 0.03);
    float lines = extrude(min(udSegment2(p.xy, float2(-0.25, -0.42), float2(0.25, -0.42)), udSegment2(p.xy, float2(-0.25, -0.55), float2(0.1, -0.55))) - 0.035, p.z - 0.04, 0.03);
    return min(min(card, clip), min(lace, min(photo, min(shoulders, lines))));
}

ORB_FORMA(tesserino)
