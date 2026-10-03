#include "../OrbShading.h"

// Agente: a briefcase, a rounded case with a seam across the front, two latches and an arched handle on top.
static float valigetta(float3 p, float) {
    float body = sdRoundBox(p - float3(0, -0.1, 0), float3(0.75, 0.5, 0.2), 0.08);
    float handle = sdTorusXY(p - float3(0, 0.4, 0), 0.2, 0.045);
    float seam = sdRoundBox(p - float3(0, 0.1, 0), float3(0.75, 0.02, 0.22), 0.015);
    float3 q = float3(abs(p.x), p.y, p.z);
    float latch = sdRoundBox(q - float3(0.32, 0.1, 0.21), float3(0.09, 0.07, 0.03), 0.02);
    return min(min(body, handle), min(seam, latch));
}

ORB_FORMA(valigetta)
