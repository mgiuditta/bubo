#include "../OrbShading.h"

// Agente · macchina remota: a satellite, a cubic body with two solar panels, turning slowly in its plane.
static float satellite(float3 p, float t) {
    p.xy = p.xy * rot(0.5 + t * 0.15);
    float body = sdRoundBox(p, float3(0.20), 0.05);
    float3 q = float3(abs(p.x), p.y, p.z);
    float panel = sdRoundBox(q - float3(0.62, 0, 0), float3(0.30, 0.20, 0.02), 0.02);
    float arm = sdSegment(q, float3(0.20, 0, 0), float3(0.34, 0, 0), 0.03);
    float dish = length(p - float3(0, 0.34, 0)) - 0.07;
    float mast = sdSegment(p, float3(0, 0.20, 0), float3(0, 0.30, 0), 0.025);
    return min(min(body, panel), min(arm, min(dish, mast)));
}

ORB_FORMA(satellite)
