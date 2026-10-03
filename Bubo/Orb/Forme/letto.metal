#include "../OrbShading.h"

// Salute · sonno: a bed in profile, a headboard, a footboard, a mattress with a blanket and a pillow.
static float letto(float3 p, float) {
    float d = sdRoundBox2(p.xy - float2(-0.78, -0.12), float2(0.05, 0.60), 0.02);
    d = min(d, sdRoundBox2(p.xy - float2(0.78, -0.30), float2(0.05, 0.40), 0.02));
    d = min(d, sdRoundBox2(p.xy - float2(0, -0.62), float2(0.80, 0.05), 0.02));
    d = min(d, sdRoundBox2(p.xy - float2(0, -0.40), float2(0.70, 0.14), 0.06));
    d = min(d, sdRoundBox2(p.xy - float2(-0.50, -0.15), float2(0.22, 0.10), 0.08));
    d = min(d, sdRoundBox2(p.xy - float2(0.20, -0.20), float2(0.45, 0.07), 0.05));
    return extrude(d, p.z, 0.10) - 0.03;
}

ORB_FORMA(letto)
