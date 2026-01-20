//
//  ErosionShaders.metal
//  from-scratch
//
//  Created by Colin Marmond on 19/01/2026.
//

#include <metal_stdlib>
using namespace metal;

static float cosineStrangeDisplacement(float2 uv) {
    return (cos(uv.x * 10.0) + sin(uv.y * 10.0)) * 0.1 +
           (cos(uv.x * 100.0) + sin(uv.y * 100.0)) * 0.02 +
           (cos(uv.x * 300.0) + sin(uv.y * 300.0)) * 0.01;
}

static float basicMountainForErosion(float2 uv) {
    return exp(-10.0 * pow(length(uv - float2(0.5)), 2)) / 2.0;
}

static float getDisplacement(float2 uv) {
    return basicMountainForErosion(uv);
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
  heightTex.write(hC, gid);
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
  uint2 gid [[thread_position_in_grid]])
{
  uint w = heightTex.get_width();
  uint h = heightTex.get_height();
  if (gid.x >= w || gid.y >= h) return;

  uint2 left  = uint2(gid.x == 0 ? 0 : gid.x - 1, gid.y);
  uint2 right = uint2(min(gid.x + 1, w - 1), gid.y);
  uint2 down  = uint2(gid.x, gid.y == 0 ? 0 : gid.y - 1);
  uint2 up    = uint2(gid.x, min(gid.y + 1, h - 1));

  float hL = heightTex.read(left)[0];
  float hR = heightTex.read(right)[0];
  float hD = heightTex.read(down)[0];
  float hU = heightTex.read(up)[0];

  float dhdx = (hR - hL) * 0.5;
  float dhdy = (hU - hD) * 0.5;
  float scale = 300.0;

  float3 N = normalize(float3(-dhdx * scale, 1.0, -dhdy * scale));
  normalTex.write(float4(N, 1.0), gid);
}
