#include "../OrbShading.h"

// Finanza · incassi: a cash register with a display on top, a keypad and a drawer that slides out.
static float cassa(float3 p, float t) {
    float body = sdRoundBox(p - float3(0, -0.4, 0), float3(0.75, 0.3, 0.3), 0.08);
    float panel = extrude(sdQuad2(p.xy, float2(-0.6, -0.1), float2(0.6, -0.1), float2(0.45, 0.35), float2(-0.45, 0.35)), p.z, 0.25);
    float display = extrude(sdRoundBox2(p.xy - float2(0, 0.6), float2(0.4, 0.2), 0.0), p.z, 0.15);
    float out = pulse(fract(t / 4.0), 0.5, 0.3);
    float drawer = sdRoundBox(p - float3(0, -0.58, 0.22 * out), float3(0.55, 0.1, 0.26), 0.03);
    float keys = min(min(length(p - float3(-0.3, 0.05, 0.27)) - 0.06, length(p - float3(0, 0.05, 0.27)) - 0.06),
                     min(length(p - float3(0.3, 0.05, 0.27)) - 0.06, length(p - float3(0, 0.22, 0.27)) - 0.06));
    return min(min(body, panel), min(display, min(drawer, keys)));
}

ORB_FORMA(cassa)
