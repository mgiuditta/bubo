#include "../OrbShading.h"

// Finanza: a rocking chair in profile, drawn in rods; it rocks back and forth on its curved runners.
static float sedia_a_dondolo(float3 p, float t) {
    p /= 1.2;
    const float2 c = float2(0, 0.45);                    // centre of the runners' arc
    float a = 0.12 * sin(t * 1.5);
    p.x += a;                                             // it rolls a little as it rocks
    float3 q = p - float3(c, 0);
    q.xy = q.xy * rot(a);
    q += float3(c, 0);
    const float r = 0.055;
    float d = sdSegment(q, float3(-0.4, -0.05, 0), float3(0.4, -0.05, 0), r);          // seat
    d = min(d, sdSegment(q, float3(-0.4, -0.05, 0), float3(-0.55, 0.8, 0), r));        // back
    d = min(d, sdSegment(q, float3(0.4, -0.05, 0), float3(0.4, 0.3, 0), r));           // front post
    d = min(d, sdSegment(q, float3(0.4, 0.3, 0), float3(-0.25, 0.3, 0), r));           // arm
    d = min(d, sdSegment(q, float3(-0.4, -0.05, 0), float3(-0.4, -0.47, 0), r));       // legs
    d = min(d, sdSegment(q, float3(0.4, -0.05, 0), float3(0.4, -0.47, 0), r));
    float2 prev = c + float2(cos(-2.18), sin(-2.18));
    for (int i = 1; i <= 6; i++) {                        // the runner: an arc under the chair
        float ang = -2.18 + float(i) * (2.18 - 0.96) / 6.0;
        float2 next = c + float2(cos(ang), sin(ang));
        d = min(d, sdSegment(q, float3(prev, 0), float3(next, 0), r * 1.3));
        prev = next;
    }
    return d * 1.2;
}

ORB_FORMA(sedia_a_dondolo)
