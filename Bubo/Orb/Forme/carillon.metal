#include "../OrbShading.h"

// Musica: a music box with its lid open behind, a little dancer on a pin and a crank on the side that turns.
static float carillon(float3 p, float t) {
    float body = sdRoundBox(p - float3(0, -0.45, 0), float3(0.7, 0.32, 0.4), 0.06);
    float3 q = p - float3(0, -0.13, -0.4);
    q.yz = q.yz * rot(0.5);
    float lid = sdRoundBox(q - float3(0, 0.4, 0), float3(0.7, 0.4, 0.04), 0.03);
    float3 hand = float3(0.95, -0.45 + 0.2 * cos(t * 2.0), 0.2 * sin(t * 2.0));
    float crank = min(sdSegment(p, float3(0.7, -0.45, 0), float3(0.95, -0.45, 0), 0.04),
                      min(sdSegment(p, float3(0.95, -0.45, 0), hand, 0.04), length(p - hand) - 0.07));
    float dancer = min(sdSegment(p, float3(0, -0.13, 0), float3(0, 0.12, 0), 0.03), length(p - float3(0, 0.17, 0)) - 0.07);
    return min(min(body, lid), min(crank, dancer));
}

ORB_FORMA(carillon)
