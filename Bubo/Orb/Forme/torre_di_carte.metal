#include "../OrbShading.h"

// Codice · fragilità: a house of cards, three storeys of leaning pairs with a card laid over each; it trembles.
static float torre_di_carte(float3 p, float t) {
    float2 c = p.xy - float2(0, -0.60);
    c = c * rot(0.02 * sin(t * 11.0)) + float2(0, -0.60);
    const float height = 0.42;
    float d = 1e3;
    for (int tier = 0; tier < 3; tier++) {
        float y0 = -0.60 + height * float(tier);
        int pairs = 3 - tier;
        for (int k = 0; k < pairs; k++) {
            float cx = (float(k) - 0.5 * float(pairs - 1)) * 0.45;
            float2 apex = float2(cx, y0 + height);
            d = min(d, udSegment2(c, float2(cx - 0.2, y0), apex));
            d = min(d, udSegment2(c, float2(cx + 0.2, y0), apex));
        }
        float reach = tier == 0 ? 0.65 : (tier == 1 ? 0.45 : 0.25);
        d = min(d, udSegment2(c, float2(-reach, y0 + height), float2(reach, y0 + height)));
    }
    return extrude(d - 0.025, p.z, 0.04) - 0.02;
}

ORB_FORMA(torre_di_carte)
