#include "../OrbShading.h"

// Distance to the upper half of the circle of radius R around the origin.
static float cuffieArc(float2 q, float R) {
    return q.y >= 0.0 ? abs(length(q) - R) : min(length(q - float2(R, 0)), length(q + float2(R, 0)));
}

// Musica: over-ear headphones, a headband and two ear cups.
static float cuffie(float3 p, float) {
    p.y += 0.07;
    float band = length(float2(cuffieArc(p.xy - float2(0, -0.10), 0.65), p.z)) - 0.07;
    float cupL = sdRoundBox(p - float3(-0.68, -0.22, 0), float3(0.14, 0.27, 0.17), 0.10);
    float cupR = sdRoundBox(p - float3(0.68, -0.22, 0), float3(0.14, 0.27, 0.17), 0.10);
    return min(band, min(cupL, cupR));
}

ORB_FORMA(cuffie)
