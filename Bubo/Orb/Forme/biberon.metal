#include "../OrbShading.h"

// Salute · neonati e allattamento: a baby bottle with graduation marks, a screw collar and a teat.
static float biberon(float3 p, float) {
    p.y += 0.05;
    float body = sdCylinder(p - float3(0, -0.28, 0), 0.26, 0.41) - 0.04;
    float collar = sdCylinder(p - float3(0, 0.2, 0), 0.34, 0.07) - 0.02;
    float teat = sdRoundCone(p, float3(0, 0.26, 0), float3(0, 0.74, 0), 0.17, 0.07);
    float marks = 9.0;
    for (int i = 0; i < 3; i++) {
        float y = -0.08 - 0.2 * float(i);
        marks = min(marks, sdSegment(p, float3(-0.1, y, 0.3), float3(0.1, y, 0.3), 0.02));
    }
    return min(min(body, collar), min(teat, marks));
}

ORB_FORMA(biberon)
