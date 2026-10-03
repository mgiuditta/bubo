#include "../OrbShading.h"

// Codice · sicurezza: a pointed shield with a raised rim and a boss in the middle.
static float scudo(float3 p, float) {
    float2 a = float2(-0.62, -0.2), b = float2(0.62, -0.2), c = float2(0, -0.9);
    float body = min(sdRoundBox2(p.xy - float2(0, 0.3), float2(0.62, 0.5), 0.0), sdQuad2(p.xy, a, b, c, 0.5 * (c + a)));
    float shield = extrude(body, p.z, 0.07);
    float rim = sdSegment(p, float3(-0.62, 0.8, 0.09), float3(0.62, 0.8, 0.09), 0.05);
    rim = min(rim, sdSegment(p, float3(0.62, 0.8, 0.09), float3(0.62, -0.2, 0.09), 0.05));
    rim = min(rim, sdSegment(p, float3(0.62, -0.2, 0.09), float3(0, -0.9, 0.09), 0.05));
    rim = min(rim, sdSegment(p, float3(0, -0.9, 0.09), float3(-0.62, -0.2, 0.09), 0.05));
    rim = min(rim, sdSegment(p, float3(-0.62, -0.2, 0.09), float3(-0.62, 0.8, 0.09), 0.05));
    float boss = length(p - float3(0, 0.1, 0.1)) - 0.12;
    return min(shield, min(rim, boss));
}

ORB_FORMA(scudo)
