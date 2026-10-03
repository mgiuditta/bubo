#include "../OrbShading.h"

// Agente: a conveyor belt on two rollers, a box on top that slides to and fro.
static float nastro(float3 p, float t) {
    p.y -= 0.25;
    float belt = extrude(udSegment2(p.xy, float2(-0.6, -0.25), float2(0.6, -0.25)) - 0.22, p.z, 0.1) - 0.03;
    float rollers = min(sdTorusXY(p - float3(-0.6, -0.25, 0.13), 0.14, 0.035), sdTorusXY(p - float3(0.6, -0.25, 0.13), 0.14, 0.035));
    float x = -0.4 + 0.8 * (0.5 - 0.5 * cos(t * 1.2));
    float box = sdRoundBox(p - float3(x, 0.17, 0), float3(0.2, 0.17, 0.18), 0.03);
    float legs = min(sdSegment(p, float3(-0.5, -0.5, 0), float3(-0.55, -0.8, 0), 0.05),
                     sdSegment(p, float3(0.5, -0.5, 0), float3(0.55, -0.8, 0), 0.05));
    return min(min(belt, rollers), min(box, legs));
}

ORB_FORMA(nastro)
