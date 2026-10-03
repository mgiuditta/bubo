#include "../OrbShading.h"

// One swim fin: a foot pocket and a widening blade, tipped about x by `flap` around the ankle.
static float pinneFin(float3 p, float tilt, float flap) {
    p.xy = p.xy * rot(tilt);
    float3 pivot = float3(0, -0.1, 0);
    p -= pivot;
    p.yz = p.yz * rot(flap);
    p += pivot;
    float blade = sdQuad2(p.xy, float2(-0.1, -0.1), float2(0.1, -0.1), float2(0.2, 0.72), float2(-0.2, 0.72));
    float pocket = sdRoundBox2(p.xy - float2(0, -0.4), float2(0.11, 0.3), 0.08);
    return extrude(min(blade, pocket), p.z, 0.04) - 0.03;
}

// Salute · movimento: two swim fins side by side, beating in turn.
static float pinne(float3 p, float t) {
    float flap = 0.45 * sin(t * 3.0);
    float left = pinneFin(p - float3(-0.33, 0, 0), -0.12, flap);
    float right = pinneFin(p - float3(0.33, 0, 0), 0.12, -flap);
    return min(left, right);
}

ORB_FORMA(pinne)
