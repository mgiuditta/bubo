#include "../OrbShading.h"

// Chat · connessione di casa: a modem with two antennas and three signal arcs between them, lit one after the other.
static float segnale(float3 p, float t) {
    p.y -= 0.05;
    float modem = sdRoundBox(p - float3(0, -0.62, 0), float3(0.68, 0.16, 0.2), 0.06);
    float3 m = float3(abs(p.x), p.y, p.z);
    float antenna = sdSegment(m, float3(0.5, -0.5, 0), float3(0.64, 0.45, 0), 0.05);
    float tips = length(m - float3(0.64, 0.47, 0)) - 0.075;
    float d = min(min(modem, antenna), tips);
    const float2 c = float2(0, -0.28);
    float dot0 = length(p - float3(c, 0)) - 0.08;
    d = min(d, dot0);
    float cycle = fract(t / 1.8) * 3.0;
    for (int k = 0; k < 3; k++) {
        float R = 0.25 + 0.2 * float(k);
        float th = 0.03 + 0.035 * pulse(cycle, float(k) + 0.5, 0.9);
        float2 a = c + R * float2(sin(-0.75), cos(-0.75));
        for (int j = 1; j <= 6; j++) {
            float ang = -0.75 + 1.5 * float(j) / 6.0;
            float2 b = c + R * float2(sin(ang), cos(ang));
            d = min(d, sdSegment(p, float3(a, 0), float3(b, 0), th));
            a = b;
        }
    }
    return d;
}

ORB_FORMA(segnale)
