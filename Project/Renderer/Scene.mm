/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The implementation of the class that describes objects in a scene.
*/

#import "Scene.h"

#import <vector>
#import <ModelIO/ModelIO.h>

using namespace simd;

MTLResourceOptions getManagedBufferStorageMode() {
#if !TARGET_OS_IPHONE
    return MTLResourceStorageModeManaged;
#else
    return MTLResourceStorageModeShared;
#endif
}

@implementation Geometry

- (instancetype)initWithDevice:(id <MTLDevice>)device
{
    self = [super init];

    if (self) {
        _device = device;
    }

    return self;
}

- (void)uploadToBuffers {
}

- (void)clear {
}

- (MTLAccelerationStructureGeometryDescriptor *)geometryDescriptor {
    return nil;
}

- (NSArray <id <MTLResource>> *)resources {
    return @[];
}

- (NSString *)intersectionFunctionName {
    return nil;
}

@end

float3 getTriangleNormal(float3 v0, float3 v1, float3 v2) {
    float3 e1 = normalize(v1 - v0);
    float3 e2 = normalize(v2 - v0);

    return cross(e1, e2);
}

@implementation TriangleGeometry {
    id <MTLBuffer> _indexBuffer;
    id <MTLBuffer> _vertexPositionBuffer;
    id <MTLBuffer> _vertexNormalBuffer;
    id <MTLBuffer> _vertexColorBuffer;
    id <MTLBuffer> _perPrimitiveDataBuffer;

    std::vector<uint16_t> _indices;
    std::vector<vector_float3> _vertices;
    std::vector<vector_float3> _normals;
    std::vector<vector_float3> _colors;
    std::vector<Triangle> _triangles;
};

- (void)uploadToBuffers {
    MTLResourceOptions options = getManagedBufferStorageMode();

    id <MTLDevice> device = self.device;

    _indexBuffer = [device newBufferWithLength:_indices.size() * sizeof(uint16_t) options:options];
    _vertexPositionBuffer = [device newBufferWithLength:_vertices.size() * sizeof(vector_float3) options:options];
    _vertexNormalBuffer = [device newBufferWithLength:_normals.size() * sizeof(vector_float3) options:options];
    _vertexColorBuffer = [device newBufferWithLength:_colors.size() * sizeof(vector_float3) options:options];
    _perPrimitiveDataBuffer = [device newBufferWithLength:_triangles.size() * sizeof(Triangle) options:options];

    memcpy(_indexBuffer.contents, _indices.data(), _indexBuffer.length);
    memcpy(_vertexPositionBuffer.contents, _vertices.data(), _vertexPositionBuffer.length);
    memcpy(_vertexNormalBuffer.contents, _normals.data(), _vertexNormalBuffer.length);
    memcpy(_vertexColorBuffer.contents, _colors.data(), _vertexColorBuffer.length);
    memcpy(_perPrimitiveDataBuffer.contents, _triangles.data(), _perPrimitiveDataBuffer.length);

#if !TARGET_OS_IPHONE
    [_indexBuffer didModifyRange:NSMakeRange(0, _indexBuffer.length)];
    [_vertexPositionBuffer didModifyRange:NSMakeRange(0, _vertexPositionBuffer.length)];
    [_vertexNormalBuffer didModifyRange:NSMakeRange(0, _vertexNormalBuffer.length)];
    [_vertexColorBuffer didModifyRange:NSMakeRange(0, _vertexColorBuffer.length)];
    [_perPrimitiveDataBuffer didModifyRange:NSMakeRange(0, _perPrimitiveDataBuffer.length)];
#endif
}

- (void)clear {
    _indices.clear();
    _vertices.clear();
    _normals.clear();
    _colors.clear();
    _triangles.clear();
}

-(void)addObjFile2:(NSString *)filename transform:(matrix_float4x4)transform {
    NSString *objFile = [[NSBundle mainBundle] pathForResource:filename ofType:@"obj"];

    if (!objFile) {
        NSLog(@"Error: File not found: %@", filename);
        return;
    }

    NSURL *url = [NSURL fileURLWithPath:objFile];
    MDLAsset *asset = [[MDLAsset alloc] initWithURL:url
                                   vertexDescriptor:nil
                                    bufferAllocator:nil];
    
    const size_t firstIndex = _indices.size();

    for (MDLObject *object in asset) {
        if (![object isKindOfClass:[MDLMesh class]]) continue;

        MDLMesh *mesh = (MDLMesh *)object;

        // Extract vertex data
        MDLVertexAttributeData *vertexData = [mesh vertexAttributeDataForAttributeNamed:MDLVertexAttributePosition];
        if (vertexData) {
            // first element of vertexData.dataStart is the first vertex
            vector_float3 *vertices = (vector_float3 *)vertexData.dataStart;
            for (NSUInteger i = 0; i < vertexData.bufferSize / vertexData.stride; i++) {
                vector_float4 vertex = vector4(vertices[i], 1.0);
                vertex = transform * vertex;
                _vertices.push_back(vertex.xyz);
            }
        }

        // Extract normal data
        MDLVertexAttributeData *normalData = [mesh vertexAttributeDataForAttributeNamed:MDLVertexAttributeNormal];
        if (normalData) {
            vector_float3 *normals = (vector_float3 *)normalData.dataStart;
            for (NSUInteger i = 0; i < normalData.bufferSize / normalData.stride; i++) {
                vector_float4 normal = vector4(normals[i], 1.0);
                _normals.push_back(normalize(normal.xyz));
            }
        }
        

        // Extract indices data
        for (MDLSubmesh *submesh in mesh.submeshes) {
            id<MDLMeshBuffer> indexBuffer = submesh.indexBuffer;
            if (!indexBuffer) continue;

            // Access the mapped index buffer
            MDLMeshBufferMap *bufferMap = [indexBuffer map];
            const void *bufferBytes = bufferMap.bytes;

            // Determine the index type (e.g., uint16_t or uint32_t)
            MDLIndexBitDepth indexBitDepth = submesh.indexType;
            NSUInteger indexSize = (indexBitDepth == MDLIndexBitDepthUInt16) ? sizeof(uint16_t) : sizeof(uint32_t);
            NSUInteger indexCount = indexBuffer.length / indexSize;

            // Get .obj indices and put them into _indices array
            for (NSUInteger i = 0; i < indexCount; i++) {
                uint16_t index = 0;
                if (indexBitDepth == MDLIndexBitDepthUInt16) {
                    index = ((uint16_t *)bufferBytes)[i];
                } else {
                    index = ((uint32_t *)bufferBytes)[i];
                }

                if (index > 0) index -= 1;  // Correcting for 1-based index in OBJ files

                _indices.push_back(index);
            }
        }
    }

    // Assign default colors
    for (NSUInteger i = 0; i < _vertices.size(); i++) {
        _colors.push_back(vector3(1.0f, 1.0f, 1.0f)); // White color for all vertices
    }

    // Create triangles from indices
    for (size_t triangleIndex = firstIndex /3; triangleIndex < _indices.size() / 3; triangleIndex++) {
        Triangle triangle;
        for (size_t i = 0; i < 3; i++) {
            const uint16_t index = _indices[firstIndex + triangleIndex * 3 + i];
            triangle.normals[i] = _normals[index];    // Assign normals from _normals array
            triangle.colors[i] = _colors[index];      // Assign colors from _colors array
        }
        _triangles.push_back(triangle);  // Add triangle to _triangles
    }
}

-(void)addObjFile:(NSString *)filename transform:(matrix_float4x4)transform {
    NSError *error = nil;
    NSString *objFile = [[NSBundle mainBundle] pathForResource:filename ofType:@"obj"];

    if (!objFile) {
        NSLog(@"Error: File not found: %@", filename);
        return;
    }

    NSString *contents = [NSString stringWithContentsOfFile:objFile encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        NSLog(@"Error reading file: %@", error);
        return;
    }

    NSArray *lines = [contents componentsSeparatedByString:@"\n"];
    const size_t firstIndex = _vertices.size();

    std::vector<uint16_t> temp_indices;

    for (NSString *line in lines) {
        if ([line hasPrefix:@"v "]) { // Vertex positions
            NSArray *components = [line componentsSeparatedByString:@" "];
            float x = [components[1] floatValue];
            float y = [components[2] floatValue];
            float z = [components[3] floatValue];
            float4 vertex = transform * vector4(x, y, z, 1.0f);
            _vertices.push_back(vertex.xyz);
            _colors.push_back(vector3(1.0f, 1.0f, 1.0f)); // Default white color
        }
        else if ([line hasPrefix:@"vn "]) { // Normals
            NSArray *components = [line componentsSeparatedByString:@" "];
            float x = [components[1] floatValue];
            float y = [components[2] floatValue];
            float z = [components[3] floatValue];
            _normals.push_back(normalize(vector3(x, y, z)));
        }
        else if ([line hasPrefix:@"f "]) { // Faces
            NSArray *components = [line componentsSeparatedByString:@" "];
            size_t vertexCount = components.count - 1; // Exclude the "f"

            std::vector<uint16_t> faceIndices;
            std::vector<uint16_t> normalIndices;

            // Parse all vertex data for the face
            for (int i = 1; i <= vertexCount; i++) {
                NSArray *indices = [components[i] componentsSeparatedByString:@"/"];

                // Parse vertex position index
                uint16_t vIndex = [indices[0] intValue] - 1;
                faceIndices.push_back(vIndex);

                // Parse normal index (if it exists)
                uint16_t nIndex = (indices.count > 2 && ![indices[2] isEqualToString:@""]) ? [indices[2] intValue] - 1 : 0;
                normalIndices.push_back(nIndex);
            }

            // Triangulate the face if it has more than 3 vertices
            for (int i = 1; i < vertexCount - 1; i++) {
                _indices.push_back(faceIndices[0]);
                _indices.push_back(faceIndices[i]);
                _indices.push_back(faceIndices[i + 1]);

                // Create triangle
                Triangle triangle;
                triangle.normals[0] = _normals[normalIndices[0]];
                triangle.normals[1] = _normals[normalIndices[i]];
                triangle.normals[2] = _normals[normalIndices[i + 1]];

                triangle.colors[0] = _colors[faceIndices[0]];
                triangle.colors[1] = _colors[faceIndices[i]];
                triangle.colors[2] = _colors[faceIndices[i + 1]];

                _triangles.push_back(triangle);
            }
        }
    }
}

    

- (void)addCubeFaceWithCubeVertices:(float3 *)cubeVertices
                              color:(float3)color
                                 i0:(uint16_t)i0
                                 i1:(uint16_t)i1
                                 i2:(uint16_t)i2
                                 i3:(uint16_t)i3
                      inwardNormals:(bool)inwardNormals
{
    const float3 v0 = cubeVertices[i0];
    const float3 v1 = cubeVertices[i1];
    const float3 v2 = cubeVertices[i2];
    const float3 v3 = cubeVertices[i3];

    float3 n0 = getTriangleNormal(v0, v1, v2);
    float3 n1 = getTriangleNormal(v0, v2, v3);

    if (inwardNormals) {
        n0 = -n0;
        n1 = -n1;
    }
    
    const size_t firstIndex = _indices.size();

    const uint16_t baseIndex = (uint16_t)_vertices.size();
    _indices.push_back(baseIndex + 0);
    _indices.push_back(baseIndex + 1);
    _indices.push_back(baseIndex + 2);
    _indices.push_back(baseIndex + 0);
    _indices.push_back(baseIndex + 2);
    _indices.push_back(baseIndex + 3);

    _vertices.push_back(v0);
    _vertices.push_back(v1);
    _vertices.push_back(v2);
    _vertices.push_back(v3);
    
    _normals.push_back(normalize(n0 + n1));
    _normals.push_back(n0);
    _normals.push_back(normalize(n0 + n1));
    _normals.push_back(n1);

    for (int i = 0; i < 4; i++)
        _colors.push_back(color);

    for (size_t triangleIndex = 0; triangleIndex < 2; triangleIndex ++)
    {
        Triangle triangle;
        for (size_t i = 0; i < 3; i++)
        {
            const uint16_t index = _indices[firstIndex + triangleIndex * 3 + i];
            triangle.normals[i] = _normals[index];
            triangle.colors[i] = _colors[index];
        }
        _triangles.push_back(triangle);
    }
}

- (void)addCubeWithFaces:(unsigned int)faceMask
                   color:(vector_float3)color
               transform:(matrix_float4x4)transform
           inwardNormals:(bool)inwardNormals
{
    float3 cubeVertices[] = {
        vector3(-0.5f, -0.5f, -0.5f),
        vector3( 0.5f, -0.5f, -0.5f),
        vector3(-0.5f,  0.5f, -0.5f),
        vector3( 0.5f,  0.5f, -0.5f),
        vector3(-0.5f, -0.5f,  0.5f),
        vector3( 0.5f, -0.5f,  0.5f),
        vector3(-0.5f,  0.5f,  0.5f),
        vector3( 0.5f,  0.5f,  0.5f),
    };

    for (int i = 0; i < 8; i++) {
        float3 vertex = cubeVertices[i];

        float4 transformedVertex = vector4(vertex.x, vertex.y, vertex.z, 1.0f);
        transformedVertex = transform * transformedVertex;

        cubeVertices[i] = transformedVertex.xyz;
    }

    uint16_t cubeIndices[][4] = {
        { 0, 4, 6, 2 },
        { 1, 3, 7, 5 },
        { 0, 1, 5, 4 },
        { 2, 6, 7, 3 },
        { 0, 2, 3, 1 },
        { 4, 5, 7, 6 }
    };

    for (unsigned face = 0; face < 6; face++) {
        if (faceMask & (1 << face)) {
            [self addCubeFaceWithCubeVertices:cubeVertices
                                        color:color
                                           i0:cubeIndices[face][0]
                                           i1:cubeIndices[face][1]
                                           i2:cubeIndices[face][2]
                                           i3:cubeIndices[face][3]
                                inwardNormals:inwardNormals];
        }
    }
}

- (MTLAccelerationStructureGeometryDescriptor *)geometryDescriptor {
    // Metal represents each piece of piece of geometry in an acceleration structure using
    // a geometry descriptor. The sample uses a triangle geometry descriptor to represent
    // triangle geometry. Each triangle geometry descriptor can have its own
    // vertex buffer, index buffer, and triangle count. The sample use a single geometry
    // descriptor because it already packed all of the vertex data into a single buffer.
    MTLAccelerationStructureTriangleGeometryDescriptor *descriptor = [MTLAccelerationStructureTriangleGeometryDescriptor descriptor];

    descriptor.indexBuffer = _indexBuffer;
    descriptor.indexType = MTLIndexTypeUInt16;

    descriptor.vertexBuffer = _vertexPositionBuffer;
    descriptor.vertexStride = sizeof(float3);
    descriptor.triangleCount = _indices.size() / 3;

#if SUPPORTS_METAL_3
    if (@available(iOS 16, macOS 13, *)) {
        descriptor.primitiveDataBuffer = _perPrimitiveDataBuffer;
        descriptor.primitiveDataStride = sizeof(Triangle);
        descriptor.primitiveDataElementSize = sizeof(Triangle);
    }
#endif

    return descriptor;
}

- (NSArray <id <MTLResource>> *)resources {
    // The colors and normals for the vertices.
    return @[ _indexBuffer, _vertexNormalBuffer, _vertexColorBuffer ];
}

@end

@implementation SphereGeometry {
    id <MTLBuffer> _sphereBuffer;
    id <MTLBuffer> _boundingBoxBuffer;
    id <MTLBuffer> _perPrimitiveDataBuffer;

    std::vector<Sphere> _spheres;
};

- (void)uploadToBuffers {
    MTLResourceOptions options = getManagedBufferStorageMode();

    id <MTLDevice> device = self.device;

    _sphereBuffer = [device newBufferWithLength:_spheres.size() * sizeof(Sphere) options:options];
    _boundingBoxBuffer = [device newBufferWithLength:_spheres.size() * sizeof(BoundingBox) options:options];

    std::vector<BoundingBox> boundingBoxes;

    // Geometry types that use custom intersection functions provide bounding boxes that enclose
    // each primitive. Metal invokes the intersection function whenever a ray potentially intersects
    // one of these bounding boxes.
    for (Sphere & sphere : _spheres) {
        BoundingBox bounds;

        bounds.min.x = sphere.origin.x - sphere.radius;
        bounds.min.y = sphere.origin.y - sphere.radius;
        bounds.min.z = sphere.origin.z - sphere.radius;

        bounds.max.x = sphere.origin.x + sphere.radius;
        bounds.max.y = sphere.origin.y + sphere.radius;
        bounds.max.z = sphere.origin.z + sphere.radius;

        boundingBoxes.push_back(bounds);
    }

    memcpy(_sphereBuffer.contents, _spheres.data(), _sphereBuffer.length);
    memcpy(_boundingBoxBuffer.contents, boundingBoxes.data(), _boundingBoxBuffer.length);

#if !TARGET_OS_IPHONE
    [_sphereBuffer didModifyRange:NSMakeRange(0, _sphereBuffer.length)];
    [_boundingBoxBuffer didModifyRange:NSMakeRange(0, _boundingBoxBuffer.length)];
#endif
}

- (void)clear {
    _spheres.clear();
}

- (void)addSphereWithOrigin:(vector_float3)origin
                     radius:(float)radius
                      color:(vector_float3)color
{
    Sphere sphere;

    sphere.origin = origin;
    sphere.radiusSquared = radius * radius;
    sphere.color = color;
    sphere.radius = radius;

    _spheres.push_back(sphere);
}

- (MTLAccelerationStructureGeometryDescriptor *)geometryDescriptor {
    // Metal represents each piece of geometry in an acceleration structure using
    // a geometry descriptor. The sample uses a bounding box geometry descriptor to
    // represent a custom primitive type.

    MTLAccelerationStructureBoundingBoxGeometryDescriptor *descriptor = [MTLAccelerationStructureBoundingBoxGeometryDescriptor descriptor];

    descriptor.boundingBoxBuffer = _boundingBoxBuffer;
    descriptor.boundingBoxCount = _spheres.size();

#if SUPPORTS_METAL_3
    if (@available(iOS 16, macOS 13, *)) {
        descriptor.primitiveDataBuffer = _sphereBuffer;
        descriptor.primitiveDataStride = sizeof(Sphere);
        descriptor.primitiveDataElementSize = sizeof(Sphere);
    }
#endif

    return descriptor;
}

- (NSArray <id <MTLResource>> *)resources {
    // The sphere intersection function uses the sphere origins and radii to check for
    // intersection with rays.
    return @[ _sphereBuffer ];
}

- (NSString *)intersectionFunctionName {
    return @"sphereIntersectionFunction";
}

@end

@implementation GeometryInstance

- (instancetype)initWithGeometry:(Geometry *)geometry
                       transform:(matrix_float4x4)transform
                            mask:(unsigned int)mask
{
    self = [super init];

    if (self) {
        _geometry = geometry;
        _transform = transform;
        _mask = mask;
    }

    return self;
}

@end

@implementation Scene {
    NSMutableArray <Geometry *> *_geometries;
    NSMutableArray <GeometryInstance *> *_instances;

    std::vector<AreaLight> _lights;
}

- (NSArray <Geometry *> *)geometries {
    return _geometries;
}

- (NSUInteger)lightCount {
    return (NSUInteger)_lights.size();
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];

    if (self) {
        _device = device;

        _geometries = [[NSMutableArray alloc] init];
        _instances = [[NSMutableArray alloc] init];

        _cameraPosition = vector3(0.0f, 0.0f, -1.0f);
        _cameraTarget = vector3(0.0f, 0.0f, 0.0f);
        _cameraUp = vector3(0.0f, 1.0f, 0.0f);
    }

    return self;
}

- (void)clear {
    [_geometries removeAllObjects];
    [_instances removeAllObjects];

    _lights.clear();
}

- (void)addGeometry:(Geometry *)mesh {
    [_geometries addObject:mesh];
}

- (void)addInstance:(GeometryInstance *)instance {
    [_instances addObject:instance];
}

- (void)addLight:(AreaLight)light {
    _lights.push_back(light);
}

- (void)uploadToBuffers {
    for (Geometry *geometry in _geometries)
        [geometry uploadToBuffers];

    MTLResourceOptions options = getManagedBufferStorageMode();

    _lightBuffer = [_device newBufferWithLength:_lights.size() * sizeof(AreaLight) options:options];

    memcpy(_lightBuffer.contents, &_lights[0], _lightBuffer.length);

#if !TARGET_OS_IPHONE
    [_lightBuffer didModifyRange:NSMakeRange(0, _lightBuffer.length)];
#endif
}

+ (Scene *)newInstancedCornellBoxSceneWithDevice:(id <MTLDevice>)device
                        useIntersectionFunctions:(BOOL)useIntersectionFunctions
{
    Scene *scene = [[Scene alloc] initWithDevice:device];

    // Set up the camera.
    scene.cameraPosition = vector3(0.0f, 1.0f, 10.0f);
    scene.cameraTarget = vector3(0.0f, 1.0f, 0.0f);
    scene.cameraUp = vector3(0.0f, 1.0f, 0.0f);

    // Create a piece of triangle geometry for the light source.
    TriangleGeometry *lightMesh = [[TriangleGeometry alloc] initWithDevice:device];

    [scene addGeometry:lightMesh];
    

    matrix_float4x4 transform = matrix4x4_translation(0.0f, 1.0f, 0.0f) * matrix4x4_scale(1.0f, 3.98f, 1.0f);

    // Add the light source.
    [lightMesh addCubeWithFaces:FACE_MASK_POSITIVE_Y
                          color:vector3(1.0f, 1.0f, 1.0f)
                      transform:transform
                  inwardNormals:true];

    // Create a piece of triangle geometry for the Cornell box.
    TriangleGeometry *geometryMesh = [[TriangleGeometry alloc] initWithDevice:device];

    [scene addGeometry:geometryMesh];

    

    transform = matrix4x4_translation(0.0f, 2.0f, 0.0f) * matrix4x4_scale(4.0f, 4.0f, 4.0f);
//    matrix_float4x4 transform2 = matrix4x4_translation(0.0f, 0.0f, 0.0f) * matrix4x4_scale(8.0f, 8.0f, 8.0f);
//    //load .obj
    matrix_float4x4 transform2 = matrix4x4_translation(2.0f, -1.0f, 1.0f) * matrix4x4_scale(8.0f,8.0f, 8.0f);
    
    //matrix_float4x4 transform2 = matrix4x4_translation(0.0f, 0.0f, 0.0f) * matrix4x4_scale(1.0f, 1.0f, 1.0f);

    
    [geometryMesh addObjFile:@"bunny_plane" transform:transform2];

    //[geometryMesh addObjFile:@"cube" transform:transform2];


//
    // Add the top, bottom, and back walls.
//    [geometryMesh addCubeWithFaces:FACE_MASK_NEGATIVE_Y
//                             color:vector3(0.725f, 0.71f, 0.68f)
//                         transform:transform
//                     inwardNormals:true];

//   // Add the left wall.
//   [geometryMesh addCubeWithFaces:FACE_MASK_NEGATIVE_X
//                            color:vector3(0.63f, 0.065f, 0.05f)
//                        transform:transform
//                    inwardNormals:true];

//   // Add the right wall.
//   [geometryMesh addCubeWithFaces:FACE_MASK_POSITIVE_X
//                            color:vector3(0.14f, 0.45f, 0.091f)
//                        transform:transform
//                    inwardNormals:true];
//
//   transform = matrix4x4_translation(-0.335f, 0.6f, -0.29f) *
//               matrix4x4_rotation(0.3f, vector3(0.0f, 1.0f, 0.0f)) *
//               matrix4x4_scale(0.6f, 1.2f, 0.6f);
//
//   // Add the tall box.
//   [geometryMesh addCubeWithFaces:FACE_MASK_ALL
//                            color:vector3(0.725f, 0.71f, 0.68f)
//                        transform:transform
//                    inwardNormals:false];

    SphereGeometry *sphereGeometry = nil;

    if (!useIntersectionFunctions) {
        transform = matrix4x4_translation(0.3275f, 0.3f, 0.3725f) *
                    matrix4x4_rotation(-0.3f, vector3(0.0f, 1.0f, 0.0f)) *
                    matrix4x4_scale(0.6f, 0.6f, 0.6f);

        // If the sample isn't using intersection functions, add the short box.
//        [geometryMesh addCubeWithFaces:FACE_MASK_ALL
//                                 color:vector3(0.725f, 0.71f, 0.68f)
//                             transform:transform
//                         inwardNormals:false];
    }
    else {
        // Otherwise, create a piece of sphere geometry.
        sphereGeometry = [[SphereGeometry alloc] initWithDevice:device];

        [scene addGeometry:sphereGeometry];

        [sphereGeometry addSphereWithOrigin:vector3(0.3275f, 0.3f, 0.3725f)
                                     radius:0.3f
                                      color:vector3(0.725f, 0.71f, 0.68f)];
    }

    // Create nine instances of the scene.
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            matrix_float4x4 transform = matrix4x4_translation(x * 2.5f, y * 2.5f, 0.0f);
            
            
           // GeometryInstance *bunnyMeshInstance = [[GeometryInstance alloc] initwi]
            // Create an instance of the light.
            GeometryInstance *lightMeshInstance = [[GeometryInstance alloc] initWithGeometry:lightMesh
                                                                                   transform:transform
                                                                                        mask:GEOMETRY_MASK_LIGHT];

            [scene addInstance:lightMeshInstance];

            // Create an instance of the Cornell box.
            GeometryInstance *geometryMeshInstance = [[GeometryInstance alloc] initWithGeometry:geometryMesh
                                                                                      transform:transform
                                                                                           mask:GEOMETRY_MASK_TRIANGLE];

            [scene addInstance:geometryMeshInstance];

            // Create an instance of the sphere.
            if (useIntersectionFunctions) {
                GeometryInstance *sphereGeometryInstance = [[GeometryInstance alloc] initWithGeometry:sphereGeometry
                                                                                            transform:transform
                                                                                                 mask:GEOMETRY_MASK_SPHERE];

                [scene addInstance:sphereGeometryInstance];
            }

            // Add a light for each box.
            AreaLight light;

            light.position = vector3(x * 2.5f, y * 2.5f + 1.98f, 0.0f);
            light.forward = vector3(0.0f, -1.0f, 0.0f);
            light.right = vector3(0.25f, 0.0f, 0.0f);
            light.up = vector3(0.0f, 0.0f, 0.25f);

            float r = (float)rand() / (float)RAND_MAX;
            float g = (float)rand() / (float)RAND_MAX;
            float b = (float)rand() / (float)RAND_MAX;

            light.color = vector3(10.0f*r,10.0f*g,10.0f*b);

            [scene addLight:light];
        }
    }

    return scene;
}

@end
