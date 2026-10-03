#include "../OrbShading.h"

// Agente: a ship's wheel, a ring and a hub with eight spokes ending in handles; it turns a little each way.
static float timone(float3 p, float t) {
    float3 q = p;
    q.xy = q.xy * rot(0.25 * sin(t * 0.8));
    float d = min(sdTorusXY(q, 0.5, 0.05), length(q) - 0.14);
    for (int k = 0; k < 4; k++) {
        float an = float(k) * 0.7853982;
        float2 dir = float2(cos(an), sin(an));
        d = min(d, sdSegment(q, float3(-dir * 0.78, 0), float3(dir * 0.78, 0), 0.035));
        d = min(d, min(length(q - float3(dir * 0.85, 0)) - 0.075, length(q + float3(dir * 0.85, 0)) - 0.075));
    }
    return d;
}

ORB_FORMA(timone)
