#include "../OrbShading.h"

// Salute: a tennis racket leaning to the upper right, a round head with strings, a throat and a handle, and a ball.
static float racchetta(float3 p, float) {
    float ball = length(p - float3(-0.55, 0.5, 0)) - 0.14;
    float3 q = p;
    q.xy = q.xy * rot(0.7);
    float head = sdTorusXY(q - float3(0, 0.3, 0), 0.42, 0.04);
    float strings = min(min(sdSegment(q, float3(-0.14, -0.1, 0), float3(-0.14, 0.7, 0), 0.02), sdSegment(q, float3(0.14, -0.1, 0), float3(0.14, 0.7, 0), 0.02)),
                        min(sdSegment(q, float3(-0.39, 0.16, 0), float3(0.39, 0.16, 0), 0.02), sdSegment(q, float3(-0.39, 0.44, 0), float3(0.39, 0.44, 0), 0.02)));
    float handle = sdSegment(q, float3(0, -0.12, 0), float3(0, -0.8, 0), 0.06);
    float throat = sdSegment(float3(abs(q.x), q.y, q.z), float3(0.2, -0.04, 0), float3(0, -0.3, 0), 0.03);
    return min(min(head, strings), min(min(handle, throat), ball));
}

ORB_FORMA(racchetta)
