#include "../OrbShading.h"

// Chat · conversazione: a knight's helmet from the front, domed, with a visor bar, a nose guard and a crest.
static float elmo(float3 p, float) {
    p.y += 0.19;
    float dome = length(p - float3(0, 0.2, 0)) - 0.5;
    float lower = sdCylinder(p - float3(0, -0.2, 0), 0.46, 0.4);
    float visor = sdRoundBox(p - float3(0, 0.05, 0.42), float3(0.24, 0.06, 0.06), 0.02);
    float guard = sdRoundBox(p - float3(0, -0.22, 0.44), float3(0.05, 0.3, 0.04), 0.02);
    float crest = sdRoundBox(p - float3(0, 0.8, 0), float3(0.05, 0.18, 0.28), 0.03);
    return min(min(dome, lower), min(min(visor, guard), crest));
}

ORB_FORMA(elmo)
