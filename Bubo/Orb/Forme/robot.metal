#include "../OrbShading.h"

// Agente: a generic robot head with ears and an antenna; it blinks every few seconds.
static float robot(float3 p, float t) {
    p.y += 0.14;
    float head = sdRoundBox(p - float3(0, -0.05, 0), float3(0.56, 0.46, 0.32), 0.16);
    float3 q = float3(abs(p.x), p.y, p.z);
    float ear = sdCylinder((q - float3(0.60, -0.04, 0)).yxz, 0.12, 0.08) - 0.01;
    float close = pulse(fract(t / 4.0), 0.9, 0.03);     // 1 with the eyes shut
    float L = 0.11 * close, r = mix(0.13, 0.03, close);
    float2 e = q.xy - float2(0.24, 0.04);
    float eye = extrude(length(e - float2(clamp(e.x, -L, L), 0)) - r, p.z - 0.32, 0.05) - 0.015;
    float mouth = sdSegment(p, float3(-0.18, -0.25, 0.32), float3(0.18, -0.25, 0.32), 0.035);
    float3 a = p - float3(0, 0.41, 0);                 // the antenna sways around its base
    a.xy = a.xy * rot(0.12 * sin(t * 1.7));
    float antenna = min(sdSegment(a, float3(0), float3(0, 0.30, 0), 0.03), length(a - float3(0, 0.36, 0)) - 0.08);
    return min(min(head, ear), min(min(eye, mouth), antenna));
}

ORB_FORMA(robot)
