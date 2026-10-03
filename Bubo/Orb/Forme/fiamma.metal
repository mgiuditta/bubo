#include "../OrbShading.h"

// Meteo: a flame of three tongues rising from a round base; the tips tremble at their own pace.
static float fiamma(float3 p, float t) {
    float2 l = 0.05 * float2(sin(t * 6.0), 0.8 * sin(t * 7.7));
    float2 c = 0.04 * float2(sin(t * 8.5), 0.8 * sin(t * 6.4));
    float2 r = 0.05 * float2(sin(t * 7.3), 0.8 * sin(t * 9.1));
    float middle = sdRoundCone(p, float3(0, -0.45, 0), float3(float2(0, 0.78) + c, 0), 0.38, 0.04);
    float left = sdRoundCone(p, float3(-0.15, -0.4, 0), float3(float2(-0.4, 0.45) + l, 0), 0.3, 0.04);
    float right = sdRoundCone(p, float3(0.15, -0.4, 0), float3(float2(0.38, 0.4) + r, 0), 0.3, 0.04);
    return min(middle, min(left, right));
}

ORB_FORMA(fiamma)
