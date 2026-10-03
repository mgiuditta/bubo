#include "../OrbShading.h"

// Musica: a jukebox, a box with an arched top, two side pilasters, an arch ring on the front and three buttons.
static float jukebox(float3 p, float) {
    float body = sdRoundBox(p - float3(0, -0.25, 0), float3(0.55, 0.5, 0.3), 0.05);
    float arch = extrude(length(p.xy - float2(0, 0.25)) - 0.51, p.z, 0.26) - 0.04;
    float pilasters = sdSegment(float3(abs(p.x), p.y, p.z), float3(0.58, -0.6, 0), float3(0.58, 0.25, 0), 0.1);
    float base = sdRoundBox(p - float3(0, -0.78, 0), float3(0.62, 0.07, 0.3), 0.03);
    float ring = sdTorusXY(p - float3(0, 0.25, 0.3), 0.35, 0.04);
    float buttons = min(length(p - float3(-0.2, -0.5, 0.3)) - 0.06, min(length(p - float3(0, -0.5, 0.3)) - 0.06, length(p - float3(0.2, -0.5, 0.3)) - 0.06));
    return min(min(body, arch), min(pilasters, min(base, min(ring, buttons))));
}

ORB_FORMA(jukebox)
