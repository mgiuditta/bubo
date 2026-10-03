#include "../OrbShading.h"

// Chat: a washing machine, a tall box with a round porthole whose drum spokes turn, and two knobs.
static float lavatrice(float3 p, float t) {
    float body = sdRoundBox(p, float3(0.62, 0.8, 0.3), 0.07);
    float3 q = p - float3(0, -0.12, 0.34);
    float door = sdTorusXY(q, 0.34, 0.07);
    float d = min(body, door);
    for (int s = 0; s < 3; s++) {
        float a = t * 1.5 + float(s) * 2.0944;
        d = min(d, sdSegment(q, float3(0), float3(cos(a), sin(a), 0) * 0.3, 0.04));
    }
    float knobs = min(length(p - float3(-0.35, 0.6, 0.32)) - 0.07, length(p - float3(-0.15, 0.6, 0.32)) - 0.07);
    return min(d, knobs);
}

ORB_FORMA(lavatrice)
