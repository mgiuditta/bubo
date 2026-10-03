#include "../OrbShading.h"

// Creativo: a painter's palette, a lobed board with its thumb hole open and four dabs of paint.
static float tavolozza(float3 p, float) {
    const float s = 0.8;
    float3 q = p / s + float3(0.06, -0.1, 0);
    const float2 hole = float2(0.3, -0.3);
    float d = extrude(length(q.xy - float2(-0.3, 0.2)) - 0.60, q.z, 0.05) - 0.03;
    for (int i = 0; i < 10; i++) {                     // a ring of lobes round the hole, which stays open
        float a = 6.2831853 * float(i) / 10.0;
        d = min(d, extrude(length(q.xy - hole - 0.42 * float2(cos(a), sin(a))) - 0.30, q.z, 0.05) - 0.03);
    }
    for (int i = 0; i < 4; i++) {                      // paint
        float a = 1.75 + 0.75 * float(i);
        d = min(d, extrude(length(q.xy - float2(-0.3, 0.2) - 0.38 * float2(cos(a), sin(a))) - 0.09, q.z - 0.08, 0.03) - 0.015);
    }
    return d * s;
}

ORB_FORMA(tavolozza)
