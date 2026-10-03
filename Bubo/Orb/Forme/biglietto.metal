#include "../OrbShading.h"

// Viaggi · biglietti: a ticket with a notch on each side and a dashed line along the stub.
static float biglietto(float3 p, float) {
    float d = sdRoundBox2(p.xy, float2(0.65, 0.45), 0.0);
    d = min(d, sdRoundBox2(p.xy - float2(-0.71, 0.305), float2(0.09, 0.145), 0.0));
    d = min(d, sdRoundBox2(p.xy - float2(-0.71, -0.305), float2(0.09, 0.145), 0.0));
    d = min(d, sdRoundBox2(p.xy - float2(0.71, 0.305), float2(0.09, 0.145), 0.0));
    d = min(d, sdRoundBox2(p.xy - float2(0.71, -0.305), float2(0.09, 0.145), 0.0));
    float ticket = extrude(d, p.z, 0.05) - 0.02;
    float dashes = 9.0;
    for (int i = 0; i < 3; i++) {
        float x = -0.5 + 0.3 * float(i);
        dashes = min(dashes, min(sdSegment(p, float3(x - 0.07, 0.3, 0.06), float3(x + 0.07, 0.3, 0.06), 0.03),
                                 sdSegment(p, float3(x - 0.07, -0.3, 0.06), float3(x + 0.07, -0.3, 0.06), 0.03)));
    }
    for (int j = 0; j < 4; j++) {
        float y = -0.27 + 0.18 * float(j);
        dashes = min(dashes, sdSegment(p, float3(0.4, y - 0.05, 0.06), float3(0.4, y + 0.05, 0.06), 0.03));
    }
    return min(ticket, dashes);
}

ORB_FORMA(biglietto)
