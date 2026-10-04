#include "../OrbShading.h"

// Finanza: a coin with a raised rim and a star, turned three quarters; now and then it spins once.
static float moneta(float3 p, float t) {
    float turn = 0.5 + 2.0 * M_PI_F * smoothstep(0.75, 1.0, fract(t / 6.0));
    p.xz = p.xz * rot(turn);
    float disc = extrude(length(p.xy) - 0.69, p.z, 0.05) - 0.03;
    float3 q = float3(p.xy, abs(p.z));                 // both faces alike
    float rim = sdTorusXY(q - float3(0, 0, 0.085), 0.66, 0.045);
    float star = extrude(sdStar5(p.xy, 0.36, 0.45), q.z - 0.09, 0.025) - 0.01;
    return min(disc, min(rim, star));
}

ORB_FORMA(moneta)
