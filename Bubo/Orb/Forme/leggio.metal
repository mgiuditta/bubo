#include "../OrbShading.h"

// Musica: a music stand, a board with a ledge, three staff lines and two notes, on a pole and a tripod.
static float leggio(float3 p, float) {
    float3 f = float3(abs(p.x), p.y, p.z);
    float board = sdRoundBox(p - float3(0, 0.4, 0), float3(0.5, 0.35, 0.03), 0.02);
    float ledge = sdRoundBox(p - float3(0, 0.03, 0.08), float3(0.5, 0.04, 0.08), 0.02);
    float d = min(board, ledge);
    for (int i = 0; i < 3; i++) {
        float y = 0.28 + 0.12 * float(i);
        d = min(d, sdSegment(p, float3(-0.38, y, 0.04), float3(0.38, y, 0.04), 0.02));
    }
    d = min(d, length(p - float3(-0.15, 0.4, 0.05)) - 0.07);
    d = min(d, length(p - float3(0.15, 0.46, 0.05)) - 0.07);
    d = min(d, sdSegment(p, float3(-0.08, 0.4, 0.05), float3(-0.08, 0.62, 0.05), 0.02));
    d = min(d, sdSegment(p, float3(0.22, 0.46, 0.05), float3(0.22, 0.68, 0.05), 0.02));
    d = min(d, sdSegment(p, float3(0, 0.05, 0), float3(0, -0.35, 0), 0.05));
    d = min(d, sdSegment(f, float3(0, -0.35, 0), float3(0.5, -0.9, 0), 0.04));
    return min(d, sdSegment(p, float3(0, -0.35, 0), float3(0, -0.9, -0.3), 0.04));
}

ORB_FORMA(leggio)
