//
//  CalcFlux.metal
//  from-scratch
//
//  Created by Colin Marmond on 08/02/2026.
//

#include <metal_stdlib>
#include "../CommonShaders.h"
using namespace metal;

kernel void calc_flux(
    texture2d<float, access::read> terrain [[texture(0)]],
    texture2d<float, access::read> fluxRead [[texture(1)]],
    texture2d<float, access::write> fluxWrite [[texture(2)]],
    constant HeightMapUniforms& hmU [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= terrain.get_width() || gid.y >= terrain.get_height()) return;

    int2 pos = int2(gid);
    
    // Height = Bedrock(r) + Regolith(g) + Water(b)
    float4 cell = terrain.read(gid);
    float h = cell.r + cell.g + cell.b;

    // Neighbors
  float4 terrainL = read_tex(terrain, pos + int2(-1, 0));
  float hL = terrainL.r + terrainL.g + terrainL.b;
  float4 terrainR = read_tex(terrain, pos + int2( 1, 0));
  float hR = terrainR.r + terrainR.g + terrainR.b;
  float4 terrainT = read_tex(terrain, pos + int2( 0, 1));
  float hT = terrainT.r + terrainT.g + terrainT.b;
  float4 terrainB = read_tex(terrain, pos + int2( 0,-1));
  float hB = terrainB.r + terrainB.g + terrainB.b;

    // Current Flux (Left, Right, Top, Bottom)
    float4 f = fluxRead.read(gid);

    // Update Fluxes
    // f_new = max(0, f_old + dt * A * (g * deltaH) / l)
    f.x = max(0.0, f.x + hmU.dt * hmU.A_pipe * (hmU.gravity * (h - hL)) / hmU.l_pipe); // Left
    f.y = max(0.0, f.y + hmU.dt * hmU.A_pipe * (hmU.gravity * (h - hR)) / hmU.l_pipe); // Right
    f.z = max(0.0, f.z + hmU.dt * hmU.A_pipe * (hmU.gravity * (h - hT)) / hmU.l_pipe); // Top
    f.w = max(0.0, f.w + hmU.dt * hmU.A_pipe * (hmU.gravity * (h - hB)) / hmU.l_pipe); // Bottom

    // Scaling to prevent negative water
    float totalOut = f.x + f.y + f.z + f.w;
    float currentWater = cell.b;
    float K = min(1.0, (currentWater * hmU.l_pipe * hmU.l_pipe) / (totalOut * hmU.dt + 1e-5)); // 1e-5 to avoid div/0

    f *= K;

    fluxWrite.write(f, gid);
}
