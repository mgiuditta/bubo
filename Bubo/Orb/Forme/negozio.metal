#include "../OrbShading.h"

// Finanza: a shop front with a striped, scalloped awning, a window and a door.
static float negozio(float3 p, float) {
    float body = sdRoundBox(p - float3(0, -0.31, 0), float3(0.7, 0.44, 0.28), 0.03);
    float awning = sdRoundBox(p - float3(0, 0.35, 0.02), float3(0.8, 0.22, 0.3), 0.03);
    float cap = sdRoundBox(p - float3(0, 0.63, 0), float3(0.8, 0.07, 0.28), 0.03);
    float d = min(body, min(awning, cap));
    for (int i = 0; i < 5; i++) {
        float x = -0.6 + 0.3 * float(i);
        d = min(d, sdCylinder((p - float3(x, 0.13, 0)).xzy, 0.15, 0.32));
    }
    for (int i = 0; i < 4; i++) {
        d = min(d, sdRoundBox(p - float3(-0.6 + 0.4 * float(i), 0.35, 0.02), float3(0.1, 0.2, 0.34), 0.02));
    }
    float window = sdRoundBox(p - float3(-0.28, -0.3, 0.28), float3(0.3, 0.22, 0.05), 0.02);
    float door = sdRoundBox(p - float3(0.42, -0.4, 0.28), float3(0.14, 0.35, 0.05), 0.02);
    return min(d, min(window, door));
}

ORB_FORMA(negozio)
