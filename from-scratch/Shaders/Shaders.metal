//
//  Shaders.metal
//  from-scratch
//
//  Created by Colin Marmond on 21/12/2025.
//

#include <metal_stdlib>
using namespace metal;
using namespace raytracing;

inline ray generateCameraRay(uint2 gid, uint2 viewportSize)
{
    // Map pixel center to NDC [-1, 1]
    float2 uv = (float2(gid) + 0.5) / float2(viewportSize);
    float2 ndc = uv * 2.0 - 1.0;

    // Construct a ray starting at origin pointing forward (+Z). You can extend this later.
    float3 origin = float3(0.0, 0.0, -1.5);

    // Use ndc.x/y to slightly vary direction so the image isn't uniform
    float3 dir = normalize(float3(ndc.x, -ndc.y, 1.0));

    constexpr float tMin = 0.0;
    constexpr float tMax = 1e6;

    return ray(origin, dir, tMin, tMax);
}

kernel void compute_main(texture2d<float, access::write> outTexture [[texture(0)]],
                         uint2 gid [[thread_position_in_grid]],
                         metal::raytracing::primitive_acceleration_structure accelerationStructure   [[buffer(0)]])
{
  uint2 size = uint2(outTexture.get_width(), outTexture.get_height());
  if (gid.x >= size.x || gid.y >= size.y) { return; }

  // Generate camera ray
  ray r = generateCameraRay(gid, size);

  // Intersect with the acceleration structure
  intersector<triangle_data> intersector;
  intersection_result<triangle_data> intersection = intersector.intersect(r, accelerationStructure);

  // Default background (sky-like gradient)
  float2 uv = float2(gid) / float2(size);
  float3 color = mix(float3(0.6, 0.8, 1.0), float3(0.1, 0.2, 0.4), uv.y);

  if (intersection.distance > 0.0) {
    // Interpolate vertex normals from primitive data (packed as n0, n1, n2)
    const device float* primitive_data = (const device float*)intersection.primitive_data;
    float3 n0 = float3(primitive_data[0], primitive_data[1], primitive_data[2]);
    float3 n1 = float3(primitive_data[3], primitive_data[4], primitive_data[5]);
    float3 n2 = float3(primitive_data[6], primitive_data[7], primitive_data[8]);

    float2 bc = intersection.triangle_barycentric_coord; // (b1, b2)
    float w = 1.0 - bc.x - bc.y;                         // b0
    float3 N = normalize(n0 * w + n1 * bc.x + n2 * bc.y);

    // Simple Lambert shading
    float3 L = normalize(float3(0.5, 0.8, 0.6)); // fixed light direction
    float3 V = normalize(-r.direction);          // view direction

    float ambient = 0.1;
    float ndotl = max(dot(N, L), 0.0);

    // Simple albedo to make it visible
    float3 albedo = float3(0.75, 0.65, 0.55);

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

