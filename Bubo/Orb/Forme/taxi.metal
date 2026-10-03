#include "../OrbShading.h"

// Viaggi · in taxi: a car in profile, a cabin over a long body, wheels, and the taxi sign on the roof.
static float taxi(float3 p, float) {
    p.y -= 0.1;
    float2 q = p.xy;
    float body = sdRoundBox2(q - float2(0, -0.28), float2(0.86, 0.17), 0.09);
    float cabin = sdQuad2(q, float2(-0.5, -0.1), float2(0.5, -0.1), float2(0.3, 0.26), float2(-0.3, 0.26)) - 0.04;
    float shape = extrude(min(body, cabin), p.z, 0.16) - 0.03;
    float3 m = float3(p.x, p.y, abs(p.z));
    float wheels = min(sdSegment(m, float3(-0.5, -0.5, 0.1), float3(-0.5, -0.5, 0.2), 0.17), sdSegment(m, float3(0.5, -0.5, 0.1), float3(0.5, -0.5, 0.2), 0.17));
    float roofSign = sdRoundBox(p - float3(0, 0.38, 0), float3(0.15, 0.07, 0.1), 0.03);
    float lamp = length(float3(p.x - 0.95, p.y + 0.22, p.z)) - 0.06;
    return min(min(shape, wheels), min(roofSign, lamp));
}

ORB_FORMA(taxi)
