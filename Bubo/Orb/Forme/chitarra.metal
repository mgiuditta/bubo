#include "../OrbShading.h"

// Musica: an acoustic guitar leaning to the right, with its round sound hole, bridge, neck and head.
static float chitarra(float3 p, float) {
    const float s = 0.85;
    float3 q = p / s;
    q.xy = q.xy * rot(0.7);
    q.y += 0.27;
    float lower = extrude(length(q.xy - float2(0, -0.40)) - 0.30, q.z, 0.05) - 0.06;
    float upper = extrude(length(q.xy - float2(0, 0.0)) - 0.21, q.z, 0.05) - 0.06;
    float hole = sdTorusXY(q - float3(0, -0.28, 0.10), 0.10, 0.03);
    float bridge = sdRoundBox(q - float3(0, -0.60, 0.08), float3(0.12, 0.025, 0.02), 0.01);
    float neck = sdRoundBox(q - float3(0, 0.62, 0), float3(0.05, 0.52, 0.03), 0.015);
    float head = sdRoundBox(q - float3(0, 1.22, 0), float3(0.08, 0.14, 0.03), 0.02);
    return min(min(min(lower, upper), min(hole, bridge)), min(neck, head)) * s;
}

ORB_FORMA(chitarra)
