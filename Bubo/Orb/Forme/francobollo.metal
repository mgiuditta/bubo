#include "../OrbShading.h"

// Mail · carta: a postage stamp with a scalloped edge, a framed picture and a star.
static float francobollo(float3 p, float) {
    p.xy = p.xy * rot(0.1);
    float d = extrude(sdRoundBox2(p.xy, float2(0.52, 0.68), 0.04), p.z, 0.04) - 0.01;
    for (int i = 0; i < 5; i++) {                      // the teeth along the top and the bottom
        float x = -0.5 + 0.25 * float(i);
        d = min(d, extrude(length(p.xy - float2(x, 0.68)) - 0.075, p.z, 0.04) - 0.01);
        d = min(d, extrude(length(p.xy - float2(x, -0.68)) - 0.075, p.z, 0.04) - 0.01);
    }
    for (int j = 0; j < 7; j++) {                      // and along the sides
        float y = -0.6 + 0.2 * float(j);
        d = min(d, extrude(length(p.xy - float2(0.52, y)) - 0.075, p.z, 0.04) - 0.01);
        d = min(d, extrude(length(p.xy - float2(-0.52, y)) - 0.075, p.z, 0.04) - 0.01);
    }
    float frame = extrude(abs(sdRoundBox2(p.xy, float2(0.36, 0.52), 0.03)) - 0.018, p.z - 0.06, 0.012);
    float star = extrude(sdStar5(p.xy, 0.24, 0.45), p.z - 0.06, 0.02) - 0.01;
    return min(d, min(frame, star));
}

ORB_FORMA(francobollo)
