#include "../OrbShading.h"

// Codice · scrittura: a cube seen at three quarters with rounded edges, turning slowly on its vertical axis.
static float cubo(float3 p, float t) {
    p.xz = p.xz * rot(0.6 + t * 0.4);
    p.yz = p.yz * rot(0.5);
    return sdRoundBox(p, float3(0.5), 0.1);
}

ORB_FORMA(cubo)
