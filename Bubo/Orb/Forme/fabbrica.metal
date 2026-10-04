#include "../OrbShading.h"

// Agente: a factory with a sawtooth roof and two chimneys; a thread of smoke puffs rises from the first.
static float fabbrica(float3 p, float t) {
    p /= 0.9;
    p.y += 0.2;
    float d = sdRoundBox(p - float3(0, -0.3, 0), float3(0.8, 0.3, 0.3), 0.03);
    for (int i = 0; i < 3; i++) {
        float xl = -0.8 + 0.4 * float(i);
        d = min(d, extrude(sdQuad2(p.xy, float2(xl, 0), float2(xl, 0.35), float2(xl + 0.12, 0.35), float2(xl + 0.4, 0)), p.z, 0.2) - 0.04);
    }
    d = min(d, sdRoundBox(p - float3(0.45, 0.31, 0), float3(0.08, 0.31, 0.08), 0.01));
    d = min(d, sdRoundBox(p - float3(0.7, 0.31, 0), float3(0.08, 0.31, 0.08), 0.01));
    for (int i = 0; i < 3; i++) {
        d = min(d, sdRoundBox(p - float3(-0.5 + 0.4 * float(i), -0.2, 0.3), float3(0.1, 0.1, 0.04), 0.01));
    }
    d = min(d, sdRoundBox(p - float3(0.55, -0.45, 0.3), float3(0.12, 0.15, 0.04), 0.01));
    for (int j = 0; j < 3; j++) {
        float phase = fract(t / 3.0 + float(j) / 3.0);
        float r = (0.06 + 0.08 * phase) * (1.0 - smoothstep(0.8, 1.0, phase));
        d = min(d, length(p - float3(0.45 + 0.1 * sin(phase * 6.0 + float(j)), 0.68 + 0.4 * phase, 0)) - r);
    }
    return d * 0.9;
}

ORB_FORMA(fabbrica)
