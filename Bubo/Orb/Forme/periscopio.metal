#include "../OrbShading.h"

// Ricerca · anteprima: a periscope, a vertical tube with an elbow arm at the top and one at the bottom; it turns left and right.
static float periscopio(float3 p, float t) {
    p.xz = p.xz * rot(0.5 * sin(t * 0.8));
    float tube = sdSegment(p, float3(0, -0.6, 0), float3(0, 0.6, 0), 0.17);
    float up = sdSegment(p, float3(0, 0.6, 0), float3(0.45, 0.6, 0), 0.17);
    float down = sdSegment(p, float3(0, -0.6, 0), float3(-0.45, -0.6, 0), 0.17);
    float rimUp = sdCylinder(float3(p.y - 0.6, p.x - 0.5, p.z), 0.22, 0.05) - 0.01;
    float rimDown = sdCylinder(float3(p.y + 0.6, p.x + 0.5, p.z), 0.22, 0.05) - 0.01;
    float collar = sdCylinder(p, 0.24, 0.05) - 0.01;
    return min(min(tube, collar), min(min(up, down), min(rimUp, rimDown)));
}

ORB_FORMA(periscopio)
