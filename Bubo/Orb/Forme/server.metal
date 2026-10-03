#include "../OrbShading.h"

// Codice · server: a tall narrow tower with three slots and three lights that come on in turn.
static float server(float3 p, float t) {
    float d = sdRoundBox(p, float3(0.38, 0.80, 0.28), 0.06);
    float turn = fract(t / 2.4) * 3.0;
    for (int i = 0; i < 3; i++) {
        float y = 0.45 - 0.40 * float(i);
        d = min(d, sdRoundBox(p - float3(-0.07, y, 0.29), float3(0.20, 0.06, 0.02), 0.01));
        d = min(d, length(p - float3(0.22, y, 0.30)) - (0.025 + 0.035 * pulse(turn, float(i) + 0.5, 0.5)));
    }
    return d;
}

ORB_FORMA(server)
