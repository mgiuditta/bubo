#include "../OrbShading.h"

// Codice · cache: a low wide jar with a screw lid, a ridged lid edge and a label band round its middle.
static float barattolo(float3 p, float) {
    float body = sdCylinder(p - float3(0, -0.10, 0), 0.52, 0.30) - 0.08;
    float band = sdCylinder(p - float3(0, -0.10, 0), 0.62, 0.12) - 0.01;
    float lid = sdCylinder(p - float3(0, 0.40, 0), 0.54, 0.08) - 0.04;
    float d = min(min(body, band), lid);
    for (int i = 0; i < 6; i++) {                      // ridges on the lid
        float a = 1.0471976 * float(i);
        d = min(d, sdSegment(p, float3(0.58 * cos(a), 0.34, 0.58 * sin(a)), float3(0.58 * cos(a), 0.46, 0.58 * sin(a)), 0.03));
    }
    return d;
}

ORB_FORMA(barattolo)
