#include "../OrbShading.h"

// Chat: a two-door fridge, a short freezer door over a tall one with a notch between them, handles and feet.
static float frigorifero(float3 p, float) {
    float upper = sdRoundBox(p - float3(0, 0.42, 0), float3(0.38, 0.28, 0.3), 0.07);
    float lower = sdRoundBox(p - float3(0, -0.30, 0), float3(0.38, 0.40, 0.3), 0.07);
    float core = sdRoundBox(p - float3(0, 0.12, 0), float3(0.3, 0.06, 0.26), 0.02);
    float handles = min(sdSegment(p, float3(0.24, 0.30, 0.34), float3(0.24, 0.55, 0.34), 0.04),
                        sdSegment(p, float3(0.24, 0.0, 0.34), float3(0.24, -0.30, 0.34), 0.04));
    float feet = sdCylinder(float3(abs(p.x), p.y, p.z) - float3(0.26, -0.75, 0), 0.07, 0.05);
    return min(min(upper, lower), min(core, min(handles, feet)));
}

ORB_FORMA(frigorifero)
