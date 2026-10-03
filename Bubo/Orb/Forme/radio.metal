#include "../OrbShading.h"

// Musica: a portable radio, a box with a carrying handle, a speaker ring, two knobs and an antenna that sways.
static float radio(float3 p, float t) {
    float body = sdRoundBox(p - float3(0, -0.2, 0), float3(0.72, 0.42, 0.2), 0.08);
    float handle = sdTorusXY(p - float3(0, 0.22, 0), 0.3, 0.04);
    float a = 0.35 + 0.14 * sin(t * 2.0);
    float2 root = float2(0.48, 0.22);
    float2 tip = root + 0.66 * float2(sin(a), cos(a));
    float antenna = min(sdSegment(p, float3(root, 0), float3(tip, 0), 0.03), length(p - float3(tip, 0)) - 0.06);
    float speaker = sdTorusXY(p - float3(-0.3, -0.2, 0.2), 0.18, 0.03);
    float knobs = min(length(p - float3(0.35, -0.05, 0.22)) - 0.07, length(p - float3(0.35, -0.35, 0.22)) - 0.07);
    return min(min(body, handle), min(antenna, min(speaker, knobs)));
}

ORB_FORMA(radio)
