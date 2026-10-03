#include "../OrbShading.h"

// Codice · scrittura: a coil spring of five turns between two plates; the top plate sinks and springs back.
static float molla(float3 p, float t) {
    float k = 1.0 - 0.3 * (0.5 - 0.5 * cos(t * 3.0));
    float top = -0.8 + 1.5 * k;
    float d = 9.0;
    float3 prev = float3(0.4, -0.8, 0);
    for (int i = 1; i <= 30; i++) {
        float u = float(i) / 30.0;
        float a = u * 31.4159265;
        float3 cur = float3(0.4 * cos(a), -0.8 + 1.5 * k * u, 0.4 * sin(a));
        d = min(d, sdSegment(p, prev, cur, 0.05));
        prev = cur;
    }
    float bottomPlate = sdCylinder(p - float3(0, -0.82, 0), 0.46, 0.03) - 0.02;
    float topPlate = sdCylinder(p - float3(0, top + 0.02, 0), 0.46, 0.03) - 0.02;
    return min(d, min(bottomPlate, topPlate));
}

ORB_FORMA(molla)
