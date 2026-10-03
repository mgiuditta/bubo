#include "../OrbShading.h"

// Viaggi: a camper van in profile, a tall box body with the cab jutting out at the front, a roof vent and two wheels.
static float camper(float3 p, float) {
    p.y -= 0.1;
    float body = sdRoundBox(p - float3(-0.12, 0, 0), float3(0.58, 0.34, 0.3), 0.1);
    float cab = sdRoundBox(p - float3(0.52, -0.08, 0), float3(0.32, 0.26, 0.28), 0.1);
    float vent = sdRoundBox(p - float3(-0.15, 0.4, 0), float3(0.18, 0.05, 0.16), 0.03);
    float wheels = min(extrude(length(p.xy - float2(-0.4, -0.36)) - 0.16, p.z, 0.31),
                       extrude(length(p.xy - float2(0.5, -0.36)) - 0.16, p.z, 0.31)) - 0.03;
    return min(min(body, cab), min(vent, wheels));
}

ORB_FORMA(camper)
