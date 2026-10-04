#include "../OrbShading.h"

// Codice · cifratura: a closed padlock, round shackle on a rounded body, a keyhole on its front.
static float lucchetto(float3 p, float) {
    float body = sdRoundBox(p - float3(0, -0.25, 0), float3(0.55, 0.4, 0.2), 0.1);
    const float R = 0.28, r = 0.08;
    float2 q = p.xy - float2(0, 0.2);
    float arc = q.y >= 0.0 ? length(float2(length(q) - R, p.z)) - r
                           : min(length(p - float3(R, 0.2, 0)), length(p - float3(-R, 0.2, 0))) - r;
    float legs = min(sdSegment(p, float3(R, 0.2, 0), float3(R, 0.0, 0), r), sdSegment(p, float3(-R, 0.2, 0), float3(-R, 0.0, 0), r));
    float hole = min(length(p - float3(0, -0.2, 0.2)) - 0.07, sdSegment(p, float3(0, -0.2, 0.2), float3(0, -0.4, 0.2), 0.035));
    return min(min(body, arc), min(legs, hole));
}

ORB_FORMA(lucchetto)
