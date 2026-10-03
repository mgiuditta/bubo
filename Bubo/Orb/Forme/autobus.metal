#include "../OrbShading.h"

// Viaggi: a city bus in profile, a body and a roof joined by five pillars, so four windows are left open over the glass.
static float autobus(float3 p, float) {
    float3 q = float3(abs(p.x), p.y, p.z);
    float body = sdRoundBox(p - float3(0, -0.15, 0), float3(0.85, 0.2, 0.2), 0.06);
    float roof = sdRoundBox(p - float3(0, 0.42, 0), float3(0.85, 0.05, 0.2), 0.04);
    float pillars = min(sdRoundBox(p - float3(0, 0.21, 0), float3(0.04, 0.17, 0.2), 0.03),
                        min(sdRoundBox(q - float3(0.43, 0.21, 0), float3(0.04, 0.17, 0.2), 0.03),
                            sdRoundBox(q - float3(0.82, 0.21, 0), float3(0.04, 0.17, 0.2), 0.03)));
    float glass = sdRoundBox(p - float3(0, 0.21, -0.1), float3(0.8, 0.17, 0.02), 0.015);
    float wheels = extrude(length(float2(q.x - 0.5, p.y + 0.36)) - 0.17, p.z, 0.22);
    return min(min(body, roof), min(pillars, min(glass, wheels)));
}

ORB_FORMA(autobus)
