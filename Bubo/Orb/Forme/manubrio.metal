#include "../OrbShading.h"

// A cylinder along x, from -h to h around the origin, edges rounded by e.
static float manubrioDisc(float3 p, float r, float h, float e) {
    return sdCylinder(float3(p.y, p.x, p.z), r - e, h - e) - e;
}

// Salute · pesi: a dumbbell side on, two plates a side on a short bar; it lifts and lowers.
static float manubrio(float3 p, float t) {
    p.y += 0.12 * sin(t * 1.6);
    float3 q = float3(abs(p.x), p.y, p.z);
    float bar = sdSegment(p, float3(-0.78, 0, 0), float3(0.78, 0, 0), 0.06);
    float big = manubrioDisc(q - float3(0.42, 0, 0), 0.50, 0.07, 0.03);
    float inner = manubrioDisc(q - float3(0.56, 0, 0), 0.36, 0.06, 0.03);
    float grip = sdSegment(p, float3(-0.3, 0, 0), float3(0.3, 0, 0), 0.09);
    return min(min(bar, grip), min(big, inner));
}

ORB_FORMA(manubrio)
