#include "../OrbShading.h"

// Finanza: a cash machine, a raised screen, six keys, the card slot and the cash tray jutting out at the foot.
static float bancomat(float3 p, float) {
    float body = sdRoundBox(p, float3(0.55, 0.85, 0.2), 0.1);
    float screen = sdRoundBox(p - float3(0, 0.45, 0.2), float3(0.38, 0.22, 0.04), 0.03);
    float slot = sdRoundBox(p - float3(0, -0.5, 0.2), float3(0.3, 0.04, 0.05), 0.03);
    float tray = sdRoundBox(p - float3(0, -0.7, 0.26), float3(0.38, 0.07, 0.1), 0.05);
    float d = min(min(body, screen), min(slot, tray));
    for (int row = 0; row < 2; row++) {
        for (int col = 0; col < 3; col++) {
            d = min(d, length(p - float3(-0.2 + 0.2 * float(col), 0.04 - 0.17 * float(row), 0.2)) - 0.065);
        }
    }
    return d;
}

ORB_FORMA(bancomat)
