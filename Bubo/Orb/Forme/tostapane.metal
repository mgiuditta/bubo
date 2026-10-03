#include "../OrbShading.h"

// Chat · casa: a toaster with two slices poking out of the top that pop up in turn, and a lever on the side.
static float tostapane(float3 p, float t) {
    float body = sdRoundBox(p - float3(0, -0.3, 0), float3(0.7, 0.3, 0.3), 0.12);
    float phase = fract(t / 2.5);
    float left = sdRoundBox(p - float3(-0.28, 0.12 + 0.25 * pulse(phase, 0.35, 0.15), 0), float3(0.22, 0.28, 0.06), 0.06);
    float right = sdRoundBox(p - float3(0.28, 0.12 + 0.25 * pulse(phase, 0.45, 0.15), 0), float3(0.22, 0.28, 0.06), 0.06);
    float lever = min(sdSegment(p, float3(0.66, -0.15, 0), float3(0.8, -0.15, 0), 0.03), length(p - float3(0.82, -0.15, 0)) - 0.08);
    return min(min(body, lever), min(left, right));
}

ORB_FORMA(tostapane)
