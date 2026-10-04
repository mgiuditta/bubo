#include "../OrbShading.h"

// Chat: a speech bubble with its tail down to the left; three dots on the front rise in turn, like typing.
static float fumetto(float3 p, float t) {
    float bubble2 = min(sdRoundBox2(p.xy - float2(0, 0.12), float2(0.76, 0.48), 0.26),
                        sdQuad2(p.xy, float2(-0.50, -0.20), float2(-0.14, -0.20), float2(-0.56, -0.70), float2(-0.63, -0.69)));
    float d = extrude(bubble2, p.z, 0.05) - 0.08;
    for (int i = 0; i < 3; i++) {
        float lift = max(sin(t * 4.0 - float(i) * 0.9), 0.0);
        d = min(d, length(p - float3(-0.32 + 0.32 * float(i), 0.12, 0.10 + 0.03 * lift)) - 0.085);
    }
    return d;
}

ORB_FORMA(fumetto)
