#include "../OrbShading.h"

// Chat · campagna e agricoltura: a tractor in profile, a big wheel behind, a small one in front, a cab and an exhaust.
static float trattore(float3 p, float) {
    p.y += 0.05;
    float2 q = p.xy;
    float hood = sdRoundBox2(q - float2(0.38, -0.2), float2(0.4, 0.2), 0.08);
    float cab = sdRoundBox2(q - float2(-0.3, 0.08), float2(0.28, 0.32), 0.07);
    float roof = sdRoundBox2(q - float2(-0.3, 0.46), float2(0.36, 0.05), 0.03);
    float exhaust = udSegment2(q, float2(0.62, -0.02), float2(0.62, 0.42)) - 0.04;
    float shape = extrude(min(min(hood, cab), min(roof, exhaust)), p.z, 0.14) - 0.03;
    float rear = sdSegment(p, float3(-0.4, -0.4, -0.2), float3(-0.4, -0.4, 0.2), 0.4);
    float front = sdSegment(p, float3(0.62, -0.62, -0.18), float3(0.62, -0.62, 0.18), 0.2);
    float hub = sdSegment(p, float3(-0.4, -0.4, 0.2), float3(-0.4, -0.4, 0.26), 0.12);
    return min(min(shape, min(rear, front)), hub);
}

ORB_FORMA(trattore)
