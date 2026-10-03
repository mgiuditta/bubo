#include "../OrbShading.h"

// Meteo: a dandelion, a bowed stem under a round head of fluffy seeds; one seed lets go and drifts away.
static float soffione(float3 p, float t) {
    const float3 head = float3(0, 0.2, 0);
    float d = length(p - head) - 0.1;
    d = min(d, min(sdSegment(p, float3(0, -0.95, 0), float3(0.05, -0.5, 0), 0.045), sdSegment(p, float3(0.05, -0.5, 0), float3(0, 0.1, 0), 0.045)));
    float phase = fract(t / 4.0);
    for (int i = 0; i < 18; i++) {
        float y = 1.0 - 2.0 * (float(i) + 0.5) / 18.0;
        float r = sqrt(1.0 - y * y), th = float(i) * 2.399963;
        float3 dir = float3(r * cos(th), y, r * sin(th));
        if (i == 3) {
            float size = 0.075 * (1.0 - smoothstep(0.6, 1.0, phase)) * smoothstep(0.0, 0.1, phase);
            d = min(d, length(p - head - dir * 0.52 - float3(0.5, 0.4, 0) * phase) - size);
        } else {
            d = min(d, sdSegment(p, head, head + dir * 0.52, 0.015));
            d = min(d, length(p - head - dir * 0.52) - 0.075);
        }
    }
    return d;
}

ORB_FORMA(soffione)
