#include "../OrbShading.h"

// Agente: a half-round gauge, a dial with a base line, five ticks and a needle that climbs and falls.
static float indicatore(float3 p, float t) {
    const float2 c = float2(0, -0.45);
    float2 q = p.xy - c;
    float outline = min(min(udQuarterArc(q, float2(0), 0.9, float2(1, 1)), udQuarterArc(q, float2(0), 0.9, float2(-1, 1))),
                        udSegment2(q, float2(-0.9, 0), float2(0.9, 0)));
    float d = extrude(outline - 0.05, p.z, 0.05) - 0.02;
    for (int k = 0; k < 5; k++) {
        float an = float(k) * 0.7853982;
        float2 dir = float2(cos(an), sin(an));
        d = min(d, sdSegment(p, float3(c + dir * 0.66, 0), float3(c + dir * 0.78, 0), 0.03));
    }
    float a = 1.5707963 - 0.8 * sin(t * 1.1);
    float needle = sdSegment(p, float3(c, 0.04), float3(c + 0.7 * float2(cos(a), sin(a)), 0.04), 0.04);
    return min(d, min(needle, length(p - float3(c, 0.04)) - 0.1));
}

ORB_FORMA(indicatore)
