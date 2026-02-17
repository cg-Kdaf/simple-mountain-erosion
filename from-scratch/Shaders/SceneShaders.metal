//
//  Shaders.metal
//  from-scratch
//
//  Created by Colin Marmond on 21/12/2025.
//

#include <metal_stdlib>
#include "CommonShaders.h"
using namespace metal;
using namespace raytracing;

inline ray generateCameraRay(uint2 gid, uint2 viewportSize, CameraProperties camera)
{
  // 1. Map pixel center to NDC [-1, 1]
  float2 uv = (float2(gid) + 0.5) / float2(viewportSize);
  float2 ndc = uv * 2.0 - 1.0;

  // 2. Calculate the size of the view plane based on FOV
  // tan(fov/2) gives us the height of the image plane at 1 unit distance
  float tanHalfFov = tan(camera.fovYRadians * 0.5);

  // 3. Calculate offsets on the image plane
  // Scale X by aspect ratio to prevent distortion
  float screenX = ndc.x * camera.aspect * tanHalfFov;
  
  // Invert Y because screen coordinates (Y+) usually point down,
  // while world space Up (Y+) points up.
  float screenY = -ndc.y * tanHalfFov;

  // 4. Construct direction: Forward + projected offsets on Right and Up vectors
  float3 dir = normalize(camera.forward + (camera.right * screenX) + (camera.up * screenY));

  // 5. Origin is the camera position
  float3 origin = camera.position;

  constexpr float tMin = 0.0;
  constexpr float tMax = 1e6;

  return ray(origin, dir, tMin, tMax);
}

struct Vertex {
  float3 position;
  float2 uv;
};

kernel void compute_vertices(
    device const Vertex* inVertices [[buffer(0)]],
    device Vertex* outVertices [[buffer(1)]],
    constant uint& vertexCount [[buffer(2)]],
    constant float& meshSize [[buffer(3)]],
    texture2d<float, access::read_write> heightTex [[texture(0)]],
    uint id [[thread_position_in_grid]])
{
  if (id >= vertexCount) { return; }
  
  Vertex v = inVertices[id];
  
  float4 terrain = heightTex.read(uint2(v.uv * float2(heightTex.get_width(),
                                                    heightTex.get_height()) - float2(0.5)));

  outVertices[id].position.y = v.position.y + getWholeHeight(terrain);
  outVertices[id].position.xz = v.position.xz * meshSize;
}

kernel void compute_main(texture2d<float, access::write> outTexture [[texture(0)]],
                         texture2d<float, access::read> normalTex [[texture(1)]],
                         texture2d<float, access::read> colorTex [[texture(2)]],
                         uint2 gid [[thread_position_in_grid]],
                         metal::raytracing::primitive_acceleration_structure accelerationStructure [[buffer(0)]],
                         device const Vertex* vertices [[buffer(1)]],
                         device const uint32_t* indices [[buffer(2)]],
                         constant RayTracingUniforms &rtUniforms [[buffer(3)]])
{
  uint2 size = uint2(outTexture.get_width(), outTexture.get_height());
  if (gid.x >= size.x || gid.y >= size.y) { return; }

  // Generate camera ray
  ray r = generateCameraRay(gid, size, rtUniforms.camera);

  // Intersect with the acceleration structure
  intersector<triangle_data> intersector;
  intersection_result<triangle_data> intersection = intersector.intersect(r, accelerationStructure);

  // Default background (sky-like gradient)
  float2 uv = float2(gid) / float2(size);
  float3 color = mix(float3(0.6, 0.8, 1.0), float3(0.1, 0.2, 0.4), uv.y);

  if (intersection.distance > 0.0) {
    uint triID = intersection.primitive_id;
    uint i0 = indices[triID * 3 + 0];
    uint i1 = indices[triID * 3 + 1];
    uint i2 = indices[triID * 3 + 2];
    
    float2 bc = intersection.triangle_barycentric_coord;

    // Interpolate UVs to sample normal texture
    float w0 = 1.0 - bc.x - bc.y;
    float2 uv0 = vertices[i0].uv;
    float2 uv1 = vertices[i1].uv;
    float2 uv2 = vertices[i2].uv;
    float2 interpUV = uv0 * w0 + uv1 * bc.x + uv2 * bc.y;

    // Sample normal texture using interpolated UV
    uint2 nSize = uint2(normalTex.get_width(), normalTex.get_height());
    float2 sampleF = clamp(interpUV * float2(nSize), float2(0.0), float2(nSize) - 1.0);
    uint2 sampleCoord = uint2(sampleF);
    float4 nSample = normalTex.read(sampleCoord);
    float3 N = normalize(nSample.xyz);
    
    // Simple Lambert shading
    float3 L = normalize(float3(0.5, 0.8, 0.6)); // fixed light direction
    float3 V = normalize(-r.direction);          // view direction

    float ambient = 0.1;
    float ndotl = max(dot(N, L), 0.0);

    // Simple albedo to make it visible
    float4 colored = colorTex.read(sampleCoord);
    float3 albedo = float3(0.75, 0.65, 0.55);
    albedo = float3(0.0, 0.0, 1.0) * colored.g + (1.0 - colored.g) * albedo;

    // Optional: face orientation fix (avoid backface darkening if desired)
    // if (dot(N, V) < 0.0) N = -N;

    float3 shaded = albedo * (ambient + ndotl);

    // Optional: small rim light for nicer look
    float rim = pow(clamp(1.0 - max(dot(N, V), 0.0), 0.0, 1.0), 2.0) * 0.05;
    shaded += rim;
    
    color = clamp(shaded, 0.0, 1.0);
  }
  

  outTexture.write(float4(color, 1.0), gid);
}

