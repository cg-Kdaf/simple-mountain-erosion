//
//  CommonShader.h
//  from-scratch
//
//  Created by Colin Marmond on 20/01/2026.
//

// CommonShader
#ifndef COMMONSHADERS_HEADERS
#define COMMONSHADERS_HEADERS

#include <metal_stdlib>
#include "CommonShaders-Bridging-Header.h"
using namespace metal;

inline float getWholeHeight(simd_float4 terrain) {
  return (terrain.x + terrain.y + terrain.z) / 10.0;
}

// Helper to get boundary-safe values
inline simd_float4 read_tex(texture2d<float, access::read> tex, simd_int2 pos) {
  uint w = tex.get_width();
  uint h = tex.get_height();
  pos = metal::clamp(pos, simd_int2(0), simd_int2(w - 1, h - 1));
  return tex.read(simd_uint2(pos));
}

#endif // !COMMONSHADERS_HEADERS
