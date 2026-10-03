#include "../OrbShading.h"

// Codice · infrastruttura: a fire extinguisher, its hose looping down from the valve and its lever on top.
static float estintore(float3 p, float) {
    float body = sdCylinder(p - float3(0, -0.2, 0), 0.3, 0.5);
    float band = sdCylinder(p - float3(0, -0.2, 0), 0.32, 0.1);
    float shoulder = sdRoundCone(p, float3(0, 0.3, 0), float3(0, 0.55, 0), 0.3, 0.12);
    float valve = sdRoundBox(p - float3(0, 0.66, 0), float3(0.12, 0.07, 0.07), 0.02);
    float lever = sdSegment(p, float3(0.05, 0.72, 0), float3(0.4, 0.6, 0), 0.04);
    float hose = min(sdSegment(p, float3(-0.1, 0.64, 0), float3(-0.4, 0.62, 0), 0.045),
                     min(sdSegment(p, float3(-0.4, 0.62, 0), float3(-0.52, 0.3, 0), 0.045),
                         sdSegment(p, float3(-0.52, 0.3, 0), float3(-0.5, -0.1, 0), 0.045)));
    float nozzle = sdRoundCone(p, float3(-0.5, -0.1, 0), float3(-0.5, -0.3, 0), 0.04, 0.09);
    return min(min(min(body, band), min(shoulder, valve)), min(lever, min(hose, nozzle)));
}

ORB_FORMA(estintore)
