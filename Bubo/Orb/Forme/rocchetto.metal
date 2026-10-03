#include "../OrbShading.h"

// Creativo: a spool of thread with a needle laid across it.
static float rocchetto(float3 p, float) {
    float core = sdCylinder(p, 0.36, 0.50);
    float top = sdCylinder(p - float3(0, 0.50, 0), 0.52, 0.06);
    float bottom = sdCylinder(p - float3(0, -0.50, 0), 0.52, 0.06);
    float3 tip = float3(0.55, 0.62, 0.42);
    float needle = sdSegment(p, float3(-0.55, -0.55, 0.42), tip, 0.035);
    float eye = sdTorusXY(p - (tip - float3(0.03, 0.04, 0)), 0.06, 0.02);
    return min(min(core, min(top, bottom)), min(needle, eye));
}

ORB_FORMA(rocchetto)
