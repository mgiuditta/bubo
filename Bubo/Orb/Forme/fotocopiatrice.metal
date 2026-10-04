#include "../OrbShading.h"

// Codice · scrittura: a boxy copier with its lid and paper tray; a strip of light slides along its front.
static float fotocopiatrice(float3 p, float t) {
    const float s = 0.9;
    p /= s;
    float body = sdRoundBox(p - float3(0, -0.20, 0), float3(0.80, 0.35, 0.40), 0.06);
    float lid = sdRoundBox(p - float3(0, 0.22, 0), float3(0.80, 0.08, 0.40), 0.04);
    float tray = sdRoundBox(p - float3(0.90, -0.05, 0), float3(0.20, 0.03, 0.25), 0.01);
    float out = sdRoundBox(p - float3(-0.88, -0.30, 0), float3(0.18, 0.03, 0.22), 0.01);
    float light = sdRoundBox(p - float3(0.55 * sin(t * 2.0), 0.07, 0.41), float3(0.04, 0.06, 0.03), 0.01);
    return min(min(min(body, lid), min(tray, out)), light) * s;
}

ORB_FORMA(fotocopiatrice)
