#include "../OrbShading.h"

// Chat · pesci, pesca e acquari: a fish in profile with an eye, a dorsal fin and a V tail that sweeps as it swims.
static float pesce(float3 p, float t) {
    p.x += 0.05;
    p.y -= 0.04 * sin(t * 1.5);
    float2 q = p.xy;
    float body = sdQuad2(q, float2(-0.5, 0), float2(0.02, 0.4), float2(0.62, 0), float2(0.02, -0.4)) - 0.1;
    float2 tq = (q - float2(-0.5, 0)) * rot(0.28 * sin(t * 3.0)) + float2(-0.5, 0);
    float tail = sdQuad2(tq, float2(-0.45, 0), float2(-0.95, 0.38), float2(-0.78, 0), float2(-0.95, -0.38));
    float fin = sdQuad2(q, float2(-0.08, 0.34), float2(0.2, 0.34), float2(0.08, 0.6), float2(-0.04, 0.55));
    float flesh = extrude(min(min(body, tail), fin), p.z, 0.07) - 0.03;
    float eye = length(p - float3(0.36, 0.08, 0.12)) - 0.06;
    return min(flesh, eye);
}

ORB_FORMA(pesce)
