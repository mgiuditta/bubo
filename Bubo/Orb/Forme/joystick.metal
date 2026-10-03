#include "../OrbShading.h"

// Chat · conversazione: an arcade joystick on its base with two buttons; the stick rocks side to side.
static float joystick(float3 p, float t) {
    p.y -= 0.09;
    float base = sdRoundBox(p - float3(0, -0.5, 0), float3(0.55, 0.14, 0.35), 0.08);
    float buttons = min(length(p - float3(0.38, -0.34, 0.18)) - 0.1, length(p - float3(0.18, -0.34, 0.18)) - 0.1);
    float3 q = p - float3(0, -0.36, 0);
    q.xy = q.xy * rot(0.25 * sin(t * 1.6));
    float stick = sdSegment(q, float3(0), float3(0, 0.42, 0), 0.07);
    float ball = length(q - float3(0, 0.6, 0)) - 0.2;
    return min(min(base, buttons), min(stick, ball));
}

ORB_FORMA(joystick)
