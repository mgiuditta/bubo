#include "../OrbShading.h"

// Chat · energia: a wind turbine, three blades on a tall tapering pole; the blades turn.
static float pala_eolica(float3 p, float t) {
    const float2 hub = float2(0, 0.28);
    float d = sdCappedCone(p - float3(0, -0.35, 0), 0.60, 0.10, 0.05);
    d = min(d, length(p - float3(hub, 0.04)) - 0.08);
    for (int i = 0; i < 3; i++) {
        float a = 1.5708 + t * 0.9 + float(i) * 2.0944;
        float2 tip = hub + 0.62 * float2(cos(a), sin(a));
        d = min(d, sdRoundCone(p, float3(hub, 0), float3(tip, 0), 0.06, 0.025));
    }
    return d;
}

ORB_FORMA(pala_eolica)
