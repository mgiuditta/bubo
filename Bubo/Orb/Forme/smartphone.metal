#include "../OrbShading.h"

// Codice · scrittura: a phone, a rounded frame around a recessed screen, a camera notch and two side buttons.
static float smartphone(float3 p, float) {
    float frame = extrude(abs(sdRoundBox2(p.xy, float2(0.34, 0.72), 0.1)) - 0.06, p.z, 0.06);
    float screen = sdRoundBox(p - float3(0, 0, -0.03), float3(0.32, 0.70, 0.025), 0.02);
    float notch = sdRoundBox(p - float3(0, 0.62, 0), float3(0.1, 0.03, 0.07), 0.03);
    float button = sdRoundBox(p - float3(0.44, 0.3, 0), float3(0.025, 0.1, 0.03), 0.02);
    return min(min(frame, screen), min(notch, button));
}

ORB_FORMA(smartphone)
