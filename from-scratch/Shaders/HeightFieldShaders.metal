//
//  ErosionShaders.metal
//  from-scratch
//
//  Created by Colin Marmond on 19/01/2026.
//

#include <metal_stdlib>
#include "CommonShaders.h"
using namespace metal;

static float basicMountainForErosion(float2 uv) {
  float h = exp(-10.0 * pow(length(uv - float2(0.5)), 2)) / 2.0;
  float details = cos(uv.x * 10.0) + cos (uv.y * 10.0);
  float details2 = cos(uv.x * 100.0) + cos (uv.y * 100.0);
  
  return pow(h, 4.0) * 10.0 + details * 0.06 + details2 * 0.003;
}

static float getDisplacement(float2 uv) {
    return basicMountainForErosion(uv) * 1000.0;
}

kernel void reset_heightmap(
  texture2d<float, access::read_write> heightTex [[texture(0)]],
  uint2 gid [[thread_position_in_grid]])
{
  uint width = heightTex.get_width();
  uint height = heightTex.get_height();
  if (gid.x >= width || gid.y >= height) { return; }

  float2 uv = (float2(gid) + 0.5) / float2(width, height);

  float hC = getDisplacement(uv);
  heightTex.write(float4(max(0.0, hC) + 3.0, 50.0, (length(uv - float2(0.5)) < 0.1) * 0.5, 0.0), gid);
}

kernel void live_animation_heightmap(
  texture2d<float, access::read_write> heightTex [[texture(0)]],
  constant float& time [[buffer(0)]],
  uint2 gid [[thread_position_in_grid]])
{
  uint width = heightTex.get_width();
  uint height = heightTex.get_height();
  if (gid.x >= width || gid.y >= height) { return; }

  float2 uv = (float2(gid) + 0.5) / float2(width, height) + float2(time);

  // Write center height
  float hC = getDisplacement(uv);
  heightTex.write(hC, gid);
}

kernel void progressive_blur(
  texture2d<float, access::read_write> heightTex [[texture(0)]],
  uint2 gid [[thread_position_in_grid]])
{
  uint width = heightTex.get_width();
  uint height = heightTex.get_height();
  if (gid.x >= width || gid.y >= height) { return; }

  float acc = 0.0;
  acc += heightTex.read(gid + uint2(0, 1))[0];
  acc += heightTex.read(gid + uint2(1, 0))[0];
  acc += heightTex.read(gid + uint2(0, -1))[0];
  acc += heightTex.read(gid + uint2(-1, 0))[0];
  
  float ratio = 0.9;
  float new_height = heightTex.read(gid)[0] * ratio + (1.0 - ratio) * acc / 4.0;
  
  heightTex.write(new_height, gid);
}

kernel void recalculate_normals(
  texture2d<float, access::read_write> heightTex [[texture(0)]],
  texture2d<float, access::read_write> normalTex [[texture(1)]],
  constant HeightMapUniforms& hmU [[buffer(0)]],
  uint2 gid [[thread_position_in_grid]])
{
  uint w = heightTex.get_width();
  uint h = heightTex.get_height();
  if (gid.x >= w || gid.y >= h) return;

  uint2 left  = uint2(gid.x == 0 ? 0 : gid.x - 1, gid.y);
  uint2 right = uint2(min(gid.x + 1, w - 1), gid.y);
  uint2 down  = uint2(gid.x, gid.y == 0 ? 0 : gid.y - 1);
  uint2 up    = uint2(gid.x, min(gid.y + 1, h - 1));

  float hL = getWholeHeight(heightTex.read(left));
  float hR = getWholeHeight(heightTex.read(right));
  float hD = getWholeHeight(heightTex.read(down));
  float hU = getWholeHeight(heightTex.read(up));

  float dhdx = (hR - hL) * 0.5;
  float dhdy = (hU - hD) * 0.5;

  float3 N = normalize(float3(-dhdx / hmU.deltaX, 1.0, -dhdy / hmU.deltaY));
  normalTex.write(float4(N, 1.0), gid);
}
