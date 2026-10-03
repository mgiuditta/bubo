#include "../OrbShading.h"

// Finanza: a credit card with its chip and two lines of numbers.
static float carta_di_credito(float3 p, float) {
    float card = extrude(sdRoundBox2(p.xy, float2(0.80, 0.50), 0.10), p.z, 0.04) - 0.02;
    float chip = sdRoundBox(p - float3(-0.45, 0.12, 0.07), float3(0.14, 0.10, 0.02), 0.02);
    float lines = min(sdSegment(p, float3(-0.58, -0.22, 0.07), float3(0.15, -0.22, 0.07), 0.035),
                      sdSegment(p, float3(-0.58, -0.38, 0.07), float3(-0.10, -0.38, 0.07), 0.035));
    return min(card, min(chip, lines));
}

ORB_FORMA(carta_di_credito)
