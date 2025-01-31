/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The Metal shaders used for this sample.
*/
#include "ShaderTypes.h"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

using namespace raytracing;
constant unsigned int primes[] = {
    2,   3,  5,  7,
    11, 13, 17, 19,
    23, 29, 31, 37,
    41, 43, 47, 53,
    59, 61, 67, 71,
    73, 79, 83, 89
};

float halton(unsigned int i, unsigned int d) {
    unsigned int b = primes[d];

    float f = 1.0f;
    float invB = 1.0f / b;

    float r = 0;

    while (i > 0) {
        f = f * invB;
        r = r + f * (i % b);
        i = i / b;
    }

    return r;
}
template<typename T, typename IndexType>
inline T interpolateVertexAttribute(device T *attributes,
                                    IndexType i0,
                                    IndexType i1,
                                    IndexType i2,
                                    float2 uv) {
    // Look up value for each vertex.
    const T T0 = attributes[i0];
    const T T1 = attributes[i1];
    const T T2 = attributes[i2];

    // Compute the sum of the vertex attributes weighted by the barycentric coordinates.
    // The barycentric coordinates sum to one.
    return (1.0f - uv.x - uv.y) * T0 + uv.x * T1 + uv.y * T2;
}

template<typename T>
inline T interpolateVertexAttribute(thread T *attributes, float2 uv) {
    // Look up the value for each vertex.
    const T T0 = attributes[0];
    const T T1 = attributes[1];
    const T T2 = attributes[2];

    // Compute the sum of the vertex attributes weighted by the barycentric coordinates.
    // The barycentric coordinates sum to one.
    return (1.0f - uv.x - uv.y) * T0 + uv.x * T1 + uv.y * T2;
}

// Uses the inversion method to map two uniformly random numbers to a 3D
// unit hemisphere, where the probability of a given sample is proportional to the cosine
// of the angle between the sample direction and the "up" direction (0, 1, 0).
inline float3 sampleCosineWeightedHemisphere(float2 u) {
    float phi = 2.0f * M_PI_F * u.x;

    float cos_phi;
    float sin_phi = sincos(phi, cos_phi);

    float cos_theta = sqrt(u.y);
    float sin_theta = sqrt(1.0f - cos_theta * cos_theta);

    return float3(sin_theta * cos_phi, cos_theta, sin_theta * sin_phi);
}

// Maps two uniformly random numbers to the surface of a 2D area light
// source and returns the direction to this point, the amount of light that travels
// between the intersection point and the sample point on the light source, as well
// as the distance between these two points.

inline void sampleAreaLight(constant AreaLight & light,
                            float2 u,
                            float3 position,
                            thread float3 & lightDirection,
                            thread float3 & lightColor,
                            thread float & lightDistance)
{
    // Map to -1..1
    u = u * 2.0f - 1.0f;

    // Transform into the light's coordinate system.
    float3 samplePosition = light.position +
                            light.right * u.x +
                            light.up * u.y;

    // Compute the vector from sample point on  the light source to intersection point.
    lightDirection = samplePosition - position;

    lightDistance = length(lightDirection);

    float inverseLightDistance = 1.0f / max(lightDistance, 1e-3f);

    // Normalize the light direction.
    lightDirection *= inverseLightDistance;

    // Start with the light's color.
    lightColor = light.color;

    // Light falls off with the inverse square of the distance to the intersection point.
//    lightColor *= (inverseLightDistance * inverseLightDistance);
    lightColor *= (inverseLightDistance * inverseLightDistance);

    // Light also falls off with the cosine of the angle between the intersection point
    // and the light source.
    lightColor *= saturate(dot(-lightDirection, light.forward));
}


inline void sampleDirectionalLight(thread float3 & lightDirection,
                                   thread float3 & lightColor,
                                   thread float & lightDistance)
{
    lightDirection = float3(10.0f, 20.0f, -20.0f);
    lightColor = float3(1.0f, 1.0f, 1.0f);
    lightDistance = 1.0f;
}


// Aligns a direction on the unit hemisphere such that the hemisphere's "up" direction
// (0, 1, 0) maps to the given surface normal direction.
inline float3 alignHemisphereWithNormal(float3 sample, float3 normal) {
    // Set the "up" vector to the normal
    float3 up = normal;

    // Find an arbitrary direction perpendicular to the normal, which becomes the
    // "right" vector.
    float3 right = normalize(cross(normal, float3(0.0072f, 1.0f, 0.0034f)));

    // Find a third vector perpendicular to the previous two, which becomes the
    // "forward" vector.
    float3 forward = cross(right, up);

    // Map the direction on the unit hemisphere to the coordinate system aligned
    // with the normal.
    return sample.x * right + sample.y * up + sample.z * forward;
}

// Return the type for a bounding box intersection function.
struct BoundingBoxIntersection {
    bool accept    [[accept_intersection]]; // Whether to accept or reject the intersection.
    float distance [[distance]];            // Distance from the ray origin to the intersection point.
};

// Resources for a piece of triangle geometry.
struct TriangleResources {
    device uint16_t *indices;
    device float3 *vertexNormals;
    device float3 *vertexColors;
};

__attribute__((always_inline))
float3 transformPoint(float3 p, float4x4 transform) {
    return (transform * float4(p.x, p.y, p.z, 1.0f)).xyz;
}

__attribute__((always_inline))
float3 transformDirection(float3 p, float4x4 transform) {
    return (transform * float4(p.x, p.y, p.z, 0.0f)).xyz;
}

// Main ray tracing kernel.
kernel void raytracingKernel(
     uint2                                                  tid                       [[thread_position_in_grid]],
     constant Uniforms &                                    uniforms                  [[buffer(0)]],
     texture2d<unsigned int>                                randomTex                 [[texture(0)]],
     texture2d<float>                                       prevTex                   [[texture(1)]],
     texture2d<float, access::write>                        dstTex                    [[texture(2)]],
     device void                                           *resources                 [[buffer(1)]],
     constant MTLAccelerationStructureInstanceDescriptor   *instances                 [[buffer(2)]],
     constant AreaLight                                    *areaLights                [[buffer(3)]],
     instance_acceleration_structure                        accelerationStructure     [[buffer(4)]]
)
{
    // The sample aligns the thread count to the threadgroup size, which means the thread count
    // may be different than the bounds of the texture. Test to make sure this thread
    // is referencing a pixel within the bounds of the texture.
    if (tid.x < uniforms.width && tid.y < uniforms.height) {
        // The ray to cast.
        ray ray;

        // Pixel coordinates for this thread.
        float2 pixel = (float2)tid;

        // Apply a random offset to the random number index to decorrelate pixels.
        unsigned int offset = randomTex.read(tid).x;

        // Add a random offset to the pixel coordinates for antialiasing.
        float2 r = float2(halton(offset + uniforms.frameIndex, 0),
                          halton(offset + uniforms.frameIndex, 1));

        pixel += r;

        // Map pixel coordinates to -1..1.
        float2 uv = (float2)pixel / float2(uniforms.width, uniforms.height);
        uv = uv * 2.0f - 1.0f;

        constant Camera & camera = uniforms.camera;

        // Rays start at the camera position.
        ray.origin = camera.position;

        // Map normalized pixel coordinates into camera's coordinate system.
        ray.direction = normalize(uv.x * camera.right +
                                  uv.y * camera.up +
                                  camera.forward);

        // Don't limit intersection distance.
        ray.max_distance = INFINITY;

        // Start with a fully white color. The kernel scales the light each time the
        // ray bounces off of a surface, based on how much of each light component
        // the surface absorbs.
        float3 color = float3(1.0f, 1.0f, 1.0f);

        float3 accumulatedColor = float3(0.0f, 0.0f, 0.0f);

        // Create an intersector to test for intersection between the ray and the geometry in the scene.
        intersector<triangle_data, instancing> i;

        // If the sample isn't using intersection functions, provide some hints to Metal for
        // better performance.
            i.assume_geometry_type(geometry_type::triangle);
            i.force_opacity(forced_opacity::opaque);

        typename intersector<triangle_data, instancing>::result_type intersection;

        // Simulate up to three ray bounces. Each bounce propagates light backward along the
        // ray's path toward the camera.
        for (int bounce = 0; bounce < 4; bounce++) {
            // Get the closest intersection, not the first intersection. This is the default, but
            // the sample adjusts this property below when it casts shadow rays.
            i.accept_any_intersection(false);

            // Check for intersection between the ray and the acceleration structure. If the sample
            // isn't using intersection functions, it doesn't need to include one.
                intersection = i.intersect(ray, accelerationStructure, bounce == 0 ? RAY_MASK_PRIMARY : RAY_MASK_SECONDARY);

            // Stop if the ray didn't hit anything and has bounced out of the scene.
            if (intersection.type == intersection_type::none)
                break;

            unsigned int instanceIndex = intersection.instance_id;

            // Look up the mask for this instance, which indicates what type of geometry the ray hit.
            unsigned int mask = instances[instanceIndex].mask;

            // If the ray hit a light source, set the color to white, and stop immediately.
            if (mask == GEOMETRY_MASK_LIGHT) {
                accumulatedColor = float3(1.0f, 1.0f, 1.0f);
                break;
            }

            // The ray hit something. Look up the transformation matrix for this instance.
            float4x4 objectToWorldSpaceTransform(1.0f);

            for (int column = 1; column < 4; column++)
                for (int row = 0; row < 3; row++)
                    objectToWorldSpaceTransform[column][row] = instances[instanceIndex].transformationMatrix[column][row];

            // Compute the intersection point in world space.
            float3 worldSpaceIntersectionPoint = ray.origin + ray.direction * intersection.distance;

            //unsigned primitiveIndex = intersection.primitive_id;
            //unsigned int geometryIndex = instances[instanceIndex].accelerationStructureIndex;
            float2 barycentric_coords = intersection.triangle_barycentric_coord;

            float3 worldSpaceSurfaceNormal = 0.0f;
            float3 surfaceColor = 0.6f;

            if (mask & GEOMETRY_MASK_TRIANGLE) {
                Triangle triangle;
                
                float3 objectSpaceSurfaceNormal;
// #if SUPPORTS_METAL_3
//                 if (usePerPrimitiveData) {
                    // Per-primitive data points to data from the specified buffer as was configured in the MTLAccelerationStructureTriangleGeometryDescriptor.
                    triangle = *(const device Triangle*)intersection.primitive_data;
                // } else
// #endif
                
                // Interpolate the vertex normal at the intersection point.
                objectSpaceSurfaceNormal = interpolateVertexAttribute(triangle.normals, barycentric_coords);

                // Interpolate the vertex color at the intersection point.
                surfaceColor = interpolateVertexAttribute(triangle.colors, barycentric_coords);

                // Transform the normal from object to world space.
                worldSpaceSurfaceNormal = normalize(transformDirection(objectSpaceSurfaceNormal, objectToWorldSpaceTransform));
            }

            // Choose a random light source to sample.
            float lightSample = halton(offset + uniforms.frameIndex, 2 + bounce * 5 + 0);
            unsigned int lightIndex = min((unsigned int)(lightSample * uniforms.lightCount), uniforms.lightCount - 1);

            // Choose a random point to sample on the light source.
            float2 r = float2(halton(offset + uniforms.frameIndex, 2 + bounce * 5 + 1),
                              halton(offset + uniforms.frameIndex, 2 + bounce * 5 + 2));

            float3 worldSpaceLightDirection;
            float3 lightColor;
            float lightDistance;

            // Sample the lighting between the intersection point and the point on the area light.
            sampleAreaLight(areaLights[lightIndex], r, worldSpaceIntersectionPoint, worldSpaceLightDirection,lightColor, lightDistance);
            //sampleDirectionalLight(worldSpaceLightDirection, lightColor, lightDistance);

            // Scale the light color by the cosine of the angle between the light direction and
            // surface normal.
            lightColor *= saturate(dot(worldSpaceSurfaceNormal, worldSpaceLightDirection));

            // Scale the light color by the number of lights to compensate for the fact that
            // the sample samples only one light source at random.
            lightColor *= uniforms.lightCount;

            // Scale the ray color by the color of the surface to simulate the surface absorbing light.
            color *= float3(0.5f);

            // Compute the shadow ray. The shadow ray checks whether the sample position on the
            // light source is visible from the current intersection point.
            // If it is, the kernel adds lighting to the output image.
            struct ray shadowRay;

            // Add a small offset to the intersection point to avoid intersecting the same
            // triangle again.
            shadowRay.origin = worldSpaceIntersectionPoint + worldSpaceSurfaceNormal * 1e-3f;

            // Travel toward the light source.
            shadowRay.direction = worldSpaceLightDirection;

            // Don't overshoot the light source.
            shadowRay.max_distance = lightDistance - 1e-3f;

            // Shadow rays check only whether there is an object between the intersection point
            // and the light source. Tell Metal to return after finding any intersection.
            i.accept_any_intersection(true);

                intersection = i.intersect(shadowRay, accelerationStructure, RAY_MASK_SHADOW);

            // If there was no intersection, then the light source is visible from the original
            // intersection  point. Add the light's contribution to the image.
            if (intersection.type == intersection_type::none)
                accumulatedColor += lightColor * color;

            // Choose a random direction to continue the path of the ray. This causes light to
            // bounce between surfaces. An app might evaluate a more complicated equation to
            // calculate the amount of light that reflects between intersection points.  However,
            // all the math in this kernel cancels out because this app assumes a simple diffuse
            // BRDF and samples the rays with a cosine distribution over the hemisphere (importance
            // sampling). This requires that the kernel only multiply the colors together. This
            // sampling strategy also reduces the amount of noise in the output image.
            r = float2(halton(offset + uniforms.frameIndex, 2 + bounce * 5 + 3),
                       halton(offset + uniforms.frameIndex, 2 + bounce * 5 + 4));

            float3 worldSpaceSampleDirection = sampleCosineWeightedHemisphere(r);
            worldSpaceSampleDirection = alignHemisphereWithNormal(worldSpaceSampleDirection, worldSpaceSurfaceNormal);

            ray.origin = worldSpaceIntersectionPoint + worldSpaceSurfaceNormal * 1e-3f;
            ray.direction = worldSpaceSampleDirection;
        }

        // Average this frame's sample with all of the previous frames.
        if (uniforms.frameIndex > 0) {
            float3 prevColor = prevTex.read(tid).xyz;
            prevColor *= uniforms.frameIndex;

            accumulatedColor += prevColor;
            accumulatedColor /= (uniforms.frameIndex + 1);
        }

        dstTex.write(float4(accumulatedColor, 1.0f), tid);
    }
}

// Screen filling quad in normalized device coordinates.
constant float2 quadVertices[] = {
    float2(-1, -1),
    float2(-1,  1),
    float2( 1,  1),
    float2(-1, -1),
    float2( 1,  1),
    float2( 1, -1)
};

struct CopyVertexOut {
    float4 position [[position]];
    float2 uv;
};

// Simple vertex shader that passes through NDC quad positions.
vertex CopyVertexOut copyVertex(unsigned short vid [[vertex_id]]) {
    float2 position = quadVertices[vid];

    CopyVertexOut out;

    out.position = float4(position, 0, 1);
    out.uv = position * 0.5f + 0.5f;

    return out;
}

// Simple fragment shader that copies a texture and applies a simple tonemapping function.
fragment float4 copyFragment(CopyVertexOut in [[stage_in]],
                             texture2d<float> tex)
{
    constexpr sampler sam(min_filter::nearest, mag_filter::nearest, mip_filter::none);

    float3 color = tex.sample(sam, in.uv).xyz;

    // Apply a simple tonemapping function to reduce the dynamic range of the
    // input image into a range which the screen can display.
    color = color / (1.0f + color);

    return float4(color, 1.0f);
}
