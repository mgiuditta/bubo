#include "../OrbShading.h"

// Mail: a mailbox on its post; now and then the flag on its side swings up.
static float cassetta_postale(float3 p, float t) {
    float box = sdRoundBox(p - float3(0, 0.3, 0), float3(0.5, 0.3, 0.28), 0.2);
    float post = sdRoundBox(p - float3(0, -0.45, 0), float3(0.07, 0.5, 0.07), 0.03);
    float knob = length(p - float3(0, 0.32, 0.32)) - 0.05;
    float cyc = fract(t / 5.0);
    float up = smoothstep(0.0, 0.2, cyc) * (1.0 - smoothstep(0.7, 0.9, cyc));
    float psi = mix(2.4, 0.0, up);                     // the flag's angle from straight up, clockwise
    const float2 pivot = float2(0.50, 0.25);
    float2 l = (p.xy - pivot) * rot(psi);
    float arm = sdSegment(float3(l, p.z), float3(0, 0, 0), float3(0, 0.4, 0), 0.035);
    float plate = sdRoundBox(float3(l, p.z) - float3(0.10, 0.31, 0), float3(0.10, 0.08, 0.02), 0.02);
    return min(min(box, post), min(knob, min(arm, plate)));
}

ORB_FORMA(cassetta_postale)
