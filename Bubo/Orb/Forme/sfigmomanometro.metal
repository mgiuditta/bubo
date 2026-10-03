#include "../OrbShading.h"

// Salute · corpo: a blood pressure cuff with its tube and bulb; the bulb is squeezed now and then.
static float sfigmomanometro(float3 p, float t) {
    p.y -= 0.2;
    float cuff = sdRoundBox(p - float3(-0.15, 0.1, 0), float3(0.45, 0.28, 0.1), 0.1);
    float tube = min(min(sdSegment(p, float3(0.3, -0.1, 0), float3(0.5, -0.35, 0), 0.035),
                         sdSegment(p, float3(0.5, -0.35, 0), float3(0.35, -0.55, 0), 0.035)),
                     sdSegment(p, float3(0.35, -0.55, 0), float3(0.1, -0.6, 0), 0.035));
    float squeeze = 0.5 + 0.5 * sin(t * 2.0);
    float bulb = sdSegment(p, float3(-0.45, -0.6, 0), float3(-0.05, -0.6, 0), 0.17 - 0.04 * squeeze);
    float valve = sdRoundBox(p - float3(-0.08, -0.6, 0), float3(0.06, 0.05, 0.05), 0.02);
    return min(min(cuff, tube), min(bulb, valve));
}

ORB_FORMA(sfigmomanometro)
