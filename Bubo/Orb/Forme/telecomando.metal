#include "../OrbShading.h"

// Agente · telefono: a long remote, a rounded frame with three round buttons inside it.
static float telecomando(float3 p, float) {
    float frame = abs(sdRoundBox2(p.xy, float2(0.28, 0.82), 0.12)) - 0.04;
    float d = extrude(frame, p.z, 0.04) - 0.03;
    for (int i = 0; i < 3; i++) {
        float2 c = float2(0, 0.40 - 0.34 * float(i));
        d = min(d, extrude(length(p.xy - c) - 0.08, p.z, 0.04) - 0.03);
    }
    return d;
}

ORB_FORMA(telecomando)
