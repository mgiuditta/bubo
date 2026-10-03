#include "../OrbShading.h"

// Chat: a loaf of bread with three scored humps on top.
static float pane(float3 p, float) {
    p.y -= 0.10;
    float d = sdSegment(p, float3(-0.42, -0.18, 0), float3(0.42, -0.18, 0), 0.36);
    for (int i = 0; i < 3; i++) {
        d = min(d, length(p - float3(-0.40 + 0.40 * float(i), 0.10, 0)) - 0.25);
    }
    return d;
}

ORB_FORMA(pane)
