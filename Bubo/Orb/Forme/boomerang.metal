#include "../OrbShading.h"

// Agente: a boomerang, a V with rounded tips, spinning flat around its own middle.
static float boomerang(float3 p, float t) {
    p.xy = p.xy * rot(t * 1.4);
    const float2 apex = float2(0.0, -0.40), tipL = float2(-0.64, 0.40), tipR = float2(0.64, 0.40);
    float d = min(udSegment2(p.xy, apex, tipL), udSegment2(p.xy, apex, tipR)) - 0.11;
    return extrude(d, p.z, 0.03) - 0.05;
}

ORB_FORMA(boomerang)
