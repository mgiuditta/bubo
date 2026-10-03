#include "../OrbShading.h"

// Chat · stampanti e scanner: a printer with a sheet in the back tray and one that slides out of the front, in and out.
static float stampante(float3 p, float t) {
    p.y -= 0.05;
    float body = sdRoundBox(p - float3(0, -0.2, 0), float3(0.78, 0.3, 0.35), 0.08);
    float tray = sdRoundBox(p - float3(0, 0.4, -0.12), float3(0.45, 0.32, 0.02), 0.01);
    float lid = sdRoundBox(p - float3(0, 0.12, -0.1), float3(0.6, 0.04, 0.2), 0.02);
    float out = 0.5 + 0.5 * sin(t * 1.5 - 1.2);
    float sheet = sdRoundBox(p - float3(0, -0.5 - 0.3 * out, 0.34), float3(0.4, 0.2, 0.015), 0.01);
    float button = length(p - float3(0.6, -0.1, 0.4)) - 0.05;
    return min(min(body, tray), min(min(lid, sheet), button));
}

ORB_FORMA(stampante)
