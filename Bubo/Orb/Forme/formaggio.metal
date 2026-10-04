#include "../OrbShading.h"

// Chat · formaggi: a wedge of cheese seen from the side; the holes are rings standing on its face.
static float formaggio(float3 p, float) {
    float2 a = float2(-0.85, -0.45), b = float2(0.85, -0.45), c = float2(0.85, 0.45);
    float wedge = extrude(sdQuad2(p.xy, a, float2(0, -0.45), b, c), p.z, 0.10) - 0.05;
    float holes = min(sdTorusXY(p - float3(0.5, -0.12, 0.14), 0.14, 0.03),
                      min(sdTorusXY(p - float3(0.0, -0.24, 0.14), 0.10, 0.03),
                          sdTorusXY(p - float3(0.6, 0.14, 0.14), 0.08, 0.03)));
    return min(wedge, holes);
}

ORB_FORMA(formaggio)
