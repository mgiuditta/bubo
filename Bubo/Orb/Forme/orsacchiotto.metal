#include "../OrbShading.h"

// Chat · bambini: a teddy bear sitting up, round ears, muzzle and nose, arms resting on its belly.
static float orsacchiotto(float3 p, float) {
    float3 m = float3(abs(p.x), p.y, p.z);
    float body = length(p - float3(0, -0.28, 0)) - 0.46;
    float head = length(p - float3(0, 0.42, 0)) - 0.35;
    float ear = length(m - float3(0.27, 0.74, 0)) - 0.13;
    float muzzle = length(p - float3(0, 0.34, 0.27)) - 0.15;
    float nose = length(p - float3(0, 0.4, 0.4)) - 0.05;
    float eye = length(m - float3(0.13, 0.5, 0.3)) - 0.045;
    float arm = sdSegment(m, float3(0.4, 0.0, 0), float3(0.52, -0.3, 0.1), 0.13);
    float leg = sdSegment(m, float3(0.3, -0.7, 0.05), float3(0.48, -0.74, 0.2), 0.17);
    return min(min(min(body, head), min(ear, muzzle)), min(min(nose, eye), min(arm, leg)));
}

ORB_FORMA(orsacchiotto)
