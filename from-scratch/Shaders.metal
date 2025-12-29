//
//  Shaders.metal
//  from-scratch
//
//  Created by Colin Marmond on 21/12/2025.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
  float4 position [[attribute(0)]];
  float3 normal [[attribute(1)]];
};

struct VertexOut
{
  float4 position [[position]];
  float3 normal [[user(normal)]];
};

vertex VertexOut vertex_main(const VertexIn vertex_in [[stage_in]]) {
  VertexOut outvert;
  outvert.position = vertex_in.position;
  outvert.normal = vertex_in.normal;
  return outvert;
}

fragment float4 fragment_main(VertexOut outVert [[stage_in]]) {
  return float4(outVert.normal, 1);
}
