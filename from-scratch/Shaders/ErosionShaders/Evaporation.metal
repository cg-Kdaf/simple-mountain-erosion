//
//  Evaporation.metal
//  from-scratch
//
//  Created by Colin Marmond on 08/02/2026.
//

#include <metal_stdlib>
#include "../CommonShaders.h"
using namespace metal;

kernel void evaporation(texture2d<float, access::read> terrainRead [[texture(0)]],
                        texture2d<float, access::write> terrainWrite [[texture(1)]],
                        constant HeightMapUniforms& hmU [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= terrainRead.get_width() || gid.y >= terrainRead.get_height()) return;
  
  float4 state = terrainRead.read(gid);
  
  // Simple exponential decay
  state.g = state.g * (1.0 - hmU.Ke * hmU.dt);
  if(state.g < 0.0001) state.g = 0.0; // Cleanup threshold
  
  terrainWrite.write(state, gid);
}
