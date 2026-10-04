#include "../OrbShading.h"

// Chat · casa: a round teapot with a lid, a spout and a handle; a wisp of steam rises from the spout.
static float teiera(float3 p, float t) {
    float body = length(p - float3(0, -0.15, 0)) - 0.45;
    float lid = sdCylinder(p - float3(0, 0.27, 0), 0.22, 0.03);
    float knob = length(p - float3(0, 0.37, 0)) - 0.07;
    float spout = sdRoundCone(p, float3(0.35, -0.15, 0), float3(0.75, 0.25, 0), 0.13, 0.05);
    float handle = sdTorusXY(p - float3(-0.5, -0.1, 0), 0.22, 0.05);
    float d = min(min(body, lid), min(knob, min(spout, handle)));
    for (int j = 0; j < 3; j++) {
        float phase = fract(t / 3.0 + float(j) / 3.0);
        float r = (0.04 + 0.04 * phase) * (1.0 - smoothstep(0.7, 1.0, phase));
        d = min(d, length(p - float3(0.75 + 0.08 * sin(phase * 8.0 + float(j) * 2.0), 0.35 + 0.4 * phase, 0)) - r);
    }
    return d;
}

ORB_FORMA(teiera)
