#include "../OrbShading.h"

// Chat · serie TV e programmi: a vintage television with a screen, two knobs and two rabbit-ear antennas that sway.
static float televisore(float3 p, float t) {
    p.y += 0.1;
    float body = sdRoundBox(p - float3(0, -0.2, 0), float3(0.72, 0.46, 0.2), 0.1);
    float screen = sdRoundBox(p - float3(-0.1, -0.2, 0.2), float3(0.5, 0.33, 0.03), 0.04);
    float knobs = min(sdCylinder(float3(p.x - 0.58, p.z - 0.22, p.y + 0.02), 0.07, 0.03), sdCylinder(float3(p.x - 0.58, p.z - 0.22, p.y + 0.3), 0.07, 0.03));
    float d = min(body, min(screen, knobs));
    float a = 0.55 + 0.12 * sin(t * 2.0);
    for (int s = 0; s < 2; s++) {
        float side = s == 0 ? -1.0 : 1.0;
        float2 tip = float2(0, 0.3) + float2(side * sin(a), cos(a)) * 0.62;
        d = min(d, sdSegment(p, float3(0, 0.3, 0), float3(tip, 0), 0.035));
        d = min(d, length(p - float3(tip, 0)) - 0.065);
    }
    float feet = min(sdSegment(p, float3(-0.5, -0.7, 0), float3(-0.55, -0.82, 0), 0.05), sdSegment(p, float3(0.5, -0.7, 0), float3(0.55, -0.82, 0), 0.05));
    return min(d, feet);
}

ORB_FORMA(televisore)
