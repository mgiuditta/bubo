#include "../OrbShading.h"

// Salute: a golf club, a long shaft with a grip and a flat head, and a ball on a tee.
static float golf(float3 p, float) {
    float shaft = sdSegment(p, float3(-0.5, -0.55, 0), float3(0.6, 0.78, 0), 0.045);
    float grip = sdSegment(p, float3(0.46, 0.62, 0), float3(0.6, 0.78, 0), 0.07);
    float head = sdRoundBox(p - float3(-0.58, -0.62, 0), float3(0.22, 0.09, 0.07), 0.04);
    float ball = length(p - float3(0.2, -0.5, 0)) - 0.15;
    float tee = sdRoundCone(p, float3(0.2, -0.82, 0), float3(0.2, -0.6, 0), 0.02, 0.07);
    return min(min(shaft, grip), min(head, min(ball, tee)));
}

ORB_FORMA(golf)
