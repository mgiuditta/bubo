#include "../OrbShading.h"

// One pin, base on the origin, 0.89 tall before `s`: a belly, a narrow neck and a round head; it rocks about its base.
static float bowlingPin(float3 p, float s, float rock) {
    p /= s;
    p.xy = p.xy * rot(rock);
    float belly = sdRoundCone(p, float3(0, 0.15, 0), float3(0, 0.52, 0), 0.14, 0.09);
    float neck = sdSegment(p, float3(0, 0.52, 0), float3(0, 0.7, 0), 0.055);
    float head = length(p - float3(0, 0.78, 0)) - 0.09;
    return min(min(belly, neck), head) * s;
}

// Salute · bowling: three pins that rock on their bases, with a ball in front.
static float bowling(float3 p, float t) {
    p.y += 0.05;
    float d = bowlingPin(p - float3(-0.45, -0.5, 0), 0.72, 0.07 * sin(t * 2.0));
    d = min(d, bowlingPin(p - float3(0.45, -0.5, 0), 0.72, 0.07 * sin(t * 2.0 + 2.1)));
    d = min(d, bowlingPin(p - float3(0, -0.05, 0), 0.72, 0.07 * sin(t * 2.0 + 4.2)));
    return min(d, length(p - float3(0, -0.6, 0.3)) - 0.3);
}

ORB_FORMA(bowling)
