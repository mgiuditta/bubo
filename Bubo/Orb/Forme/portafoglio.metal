#include "../OrbShading.h"

// Finanza: a wallet with a banknote sticking out of its top, a stitched seam and a round clasp.
static float portafoglio(float3 p, float) {
    float back = sdRoundBox(p - float3(0, -0.05, -0.02), float3(0.70, 0.45, 0.08), 0.05);
    float front = sdRoundBox(p - float3(0, -0.20, 0.10), float3(0.70, 0.30, 0.08), 0.05);
    float bill = sdRoundBox(p - float3(0, 0.28, 0.04), float3(0.50, 0.35, 0.03), 0.02);
    float seam = sdSegment(p, float3(-0.62, 0.05, 0.20), float3(0.62, 0.05, 0.20), 0.025);
    float clasp = sdCylinder(float3(p.x - 0.52, p.z - 0.2, p.y + 0.2), 0.09, 0.04) - 0.02;
    return min(min(back, front), min(bill, min(seam, clasp)));
}

ORB_FORMA(portafoglio)
