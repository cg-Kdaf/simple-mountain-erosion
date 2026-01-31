//
//  CommonShaders.metal
//  from-scratch
//
//  Created by Colin Marmond on 20/01/2026.
//

#include <metal_stdlib>
using namespace metal;

float getWholeHeight(float4 terrain) {
  return (terrain.x + terrain.y /*+ terrain.z*/) / 10.0;
}
