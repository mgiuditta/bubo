#include "../OrbShading.h"

// Finanza: a round utility meter with a window of digits and a dial, a pipe above and below; the digits scroll.
static float contatore(float3 p, float t) {
    float body = extrude(length(p.xy) - 0.52, p.z, 0.16) - 0.1;
    float pipes = min(sdCylinder(p - float3(0, 0.8, 0), 0.12, 0.15), sdCylinder(p - float3(0, -0.8, 0), 0.12, 0.15));
    float window = sdRoundBox(p - float3(0, 0.15, 0.26), float3(0.4, 0.15, 0.04), 0.01);
    float dial = sdTorusXY(p - float3(0, -0.3, 0.24), 0.22, 0.04);
    float needle = sdSegment(p, float3(0, -0.3, 0.26), float3(0.14, -0.2, 0.26), 0.03);
    float d = min(min(body, pipes), min(window, min(dial, needle)));
    for (int i = 0; i < 4; i++) {
        float y = 0.15 + (fract(t * 0.5 + float(i) / 4.0) - 0.5) * 0.2;
        d = min(d, sdSegment(p, float3(-0.27 + 0.18 * float(i), y - 0.06, 0.26), float3(-0.27 + 0.18 * float(i), y + 0.06, 0.26), 0.03));
    }
    return d;
}

ORB_FORMA(contatore)
