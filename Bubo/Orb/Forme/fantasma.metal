#include "../OrbShading.h"

// Creativo: a ghost, a round head over a cylinder body with a three-pointed hem, two eyes and an open mouth; it floats.
static float fantasma(float3 p, float t) {
    p.y -= 0.13 + 0.06 * sin(t * 1.6);
    float top = length(p - float3(0, 0.2, 0)) - 0.5;
    float skirt = sdCylinder(p - float3(0, -0.2, 0), 0.5, 0.4);
    float d = min(top, skirt);
    for (int i = 0; i < 3; i++) {
        float sway = 0.03 * sin(t * 2.2 + float(i) * 2.0);
        d = min(d, sdCappedCone(p - float3((float(i) - 1.0) * 0.33 + sway, -0.76, 0), 0.2, 0.02, 0.17));
    }
    float eyes = length(float3(abs(p.x) - 0.2, p.y - 0.28, p.z - 0.46)) - 0.09;
    float mouth = sdTorusXY(p - float3(0, 0.02, 0.49), 0.1, 0.03);
    return min(d, min(eyes, mouth));
}

ORB_FORMA(fantasma)
