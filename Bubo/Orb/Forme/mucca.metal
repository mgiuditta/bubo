#include "../OrbShading.h"

// Chat · fattorie e animali da allevamento: a cow in profile, with horns, spots, four legs, an udder and a tail.
static float mucca(float3 p, float) {
    p.x += 0.12;
    p.y += 0.1;
    float2 q = p.xy;
    float body = sdRoundBox2(q - float2(0, 0.0), float2(0.5, 0.27), 0.15);
    float head = sdRoundBox2(q - float2(0.7, 0.14), float2(0.14, 0.2), 0.1);
    float muzzle = sdRoundBox2(q - float2(0.82, -0.02), float2(0.1, 0.12), 0.06);
    float legs = 9.0;
    const float lx[4] = { -0.38, -0.2, 0.26, 0.44 };
    for (int i = 0; i < 4; i++) legs = min(legs, udSegment2(q, float2(lx[i], -0.2), float2(lx[i], -0.78)) - 0.065);
    float tail = udSegment2(q, float2(-0.6, 0.2), float2(-0.72, -0.4)) - 0.03;
    float horn = udSegment2(q, float2(0.66, 0.4), float2(0.6, 0.55)) - 0.03;
    float ear = length(q - float2(0.58, 0.28)) - 0.07;
    float udder = length(q - float2(0.05, -0.28)) - 0.1;
    float shape = extrude(min(min(body, head), min(min(muzzle, legs), min(min(tail, horn), min(ear, udder)))), p.z, 0.12) - 0.04;
    float spots = min(extrude(length(q - float2(-0.2, 0.1)) - 0.12, p.z - 0.14, 0.02), extrude(length(q - float2(0.22, -0.05)) - 0.09, p.z - 0.14, 0.02)) - 0.02;
    return min(shape, spots);
}

ORB_FORMA(mucca)
