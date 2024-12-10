"use strict";

const padding = 0.0;


class Camera {
    eyePos = vec3(277.0, 275.0, -570.0);
    lookat = vec3(277.0, 275.0, 0.0);
    up = vec3(0.0, 1.0, 0.0);
    cam_const = 1.0;
};



// Create an instance of the Camera class
const camera = new Camera();

// Create a variable to store the uniform buffer
var uniforms_f, uniforms_ui;
var uniformBuffer_f, uniformBuffer_ui;
var progressiveSampling = 0;
var frameNumber = 0;
var textures;



async function load_texture(device, filename)
{
    const response = await fetch(filename);
    const blob = await response.blob();
    const img = await createImageBitmap(blob, { colorSpaceConversion: 'none' });
    const texture = device.createTexture({
    size: [img.width, img.height, 1],
    format: "rgba8unorm",
    usage: GPUTextureUsage.COPY_DST | GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.RENDER_ATTACHMENT
    });
    device.queue.copyExternalImageToTexture(
    { source: img, flipY: true },
    { texture: texture },
    { width: img.width, height: img.height },
    );
    return texture;
}

window.onload = function () { main(); }
async function main() {
    const gpu = navigator.gpu;
    const adapter = await gpu.requestAdapter();
    const device = await adapter.requestDevice();
    const canvas = document.getElementById("webgpu-canvas");
    const context = canvas.getContext("gpupresent") || canvas.getContext("webgpu");
    const canvasFormat = navigator.gpu.getPreferredCanvasFormat();
    context.configure({
        device: device,
        format: canvasFormat,
    });

    const aspect = canvas.width/canvas.height;

    
    

    const wgsl = device.createShaderModule({
        code: document.getElementById("wgsl").text
    });

    addEventListener("wheel", (event) => {
        // camera.cam_const *= 1.0 + 2.5e-4*event.deltaY;
        // uniforms_f[3] = camera.cam_const;
        // device.queue.writeBuffer(uniformBuffer_f, 0, uniforms_f);
        // console.log("camera.cam_const = " + camera.cam_const);
        // animate();
        });

    addEventListener("wheel", (event) => {
        camera.cam_const *= 1.0 + 2.5e-4*event.deltaY;
        uniforms_f[3] = camera.cam_const;
        device.queue.writeBuffer(uniformBuffer_f, 0, uniforms_f);
        console.log("camera.cam_const = " + camera.cam_const);
        animate();
        });

    const progressiveSamplingCheckbox = document.getElementById('progressiveSampling');
    
    progressiveSamplingCheckbox.addEventListener('change', function() {
            if (progressiveSamplingCheckbox.checked)
            {
                progressiveSampling = 1;
            }
            else 
            {
                progressiveSampling = 0;
            }
            uniforms_ui[0] = progressiveSampling;
            device.queue.writeBuffer(uniformBuffer_ui, 0, uniforms_ui);
            requestAnimationFrame(animate);
            console.log("progressiveSampling = " + progressiveSampling);
        });

    function animate()
        {
        console.log("animate");
        render(device, context, pipeline, textures, bindGroup);
        if (progressiveSampling == 1)
        {
            frameNumber += 1;
            uniforms_ui[3] = frameNumber;
            device.queue.writeBuffer(uniformBuffer_ui, 0, uniforms_ui);
            // add a delay
            setTimeout(() => {
                requestAnimationFrame(animate);
            }, 1000);
        }
    }

    

    const pipeline = device.createRenderPipeline({
        layout: "auto",
        vertex: {
        module: wgsl,
        entryPoint: "main_vs",
        },
        fragment: {
        module: wgsl,
        entryPoint: "main_fs",
        targets: [ { format: canvasFormat },
        { format: "rgba32float" } ]
        },
        primitive: {
        topology: "triangle-strip",
        },
    });

    uniformBuffer_f = device.createBuffer({
        label: 'uniforms_f',
        size: 48,
        usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST, });


    uniforms_f = new Float32Array([
        camera.eyePos[0], camera.eyePos[1], camera.eyePos[2], camera.cam_const,
        camera.lookat[0], camera.lookat[1], camera.lookat[2], aspect,
        camera.up[0], camera.up[1], camera.up[2], padding,
    ]);
    device.queue.writeBuffer(uniformBuffer_f, 0, uniforms_f);

    uniforms_ui = new Uint32Array([
        progressiveSampling, canvas.width, canvas.height, frameNumber
    ]);
    uniformBuffer_ui = device.createBuffer({
        label: 'uniforms_ui',
        size: uniforms_ui.byteLength,
        usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST, });
    device.queue.writeBuffer(uniformBuffer_ui, 0, uniforms_ui);

    //dropdown1.dispatchEvent(new Event('change'));

        // // Pad each vertex to have 4 components for 16-byte alignment
        // var alignedVertices = triangle.vertices.map(v => {
        //     return [v[0], v[1], v[2], 1.0]; // Add padding component
        // });
        // console.log("alignedVertices = ", alignedVertices);

        // // Flatten the array and convert it to a Float32Array
        // alignedVertices = new Float32Array(alignedVertices.flat());
        // console.log("flattened alignedVertices = ", alignedVertices);


        // var alignedIndices = new Uint32Array(triangle.faceIndices.flat());

    const obj_filename = '../data/objects/CornellBoxWithBlocks.obj';
    var drawingInfo = await readOBJFile(obj_filename, 1, true);
    console.log("drawingInfo = ", drawingInfo);
    var buffers = new Object();
    build_bsp_tree(drawingInfo, device, buffers);
    console.log("buffers: ",buffers);
    console.log(drawingInfo.materials)
    console.log(drawingInfo.mat_indices)
    console.log("light indices = ",drawingInfo.light_indices)

    
    
    //var positionsBuffer = set_up_position_buffer(device, drawingInfo.vertices);
    var indexBuffer = set_up_index_buffer(device, drawingInfo.indices);
    //var normalsBuffer = set_up_normal_buffer(device, drawingInfo.normals);
    var materialsBuffer = set_up_materials_buffer(device, drawingInfo.materials);
    //var mat_indicesBuffer = set_up_material_indices_buffer(device, drawingInfo.mat_indices);
    // drawingInfo.light_indices = new Uint32Array([0]);
    var light_indicesBuffer = set_up_lifght_indices_buffer(device, drawingInfo.light_indices);
    
    textures = new Object();
    textures.width = canvas.width;
    textures.height = canvas.height;
    textures.renderSrc = device.createTexture({
    size: [canvas.width, canvas.height],
    usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC,
    format: 'rgba32float',
    });
    textures.renderDst = device.createTexture({
    size: [canvas.width, canvas.height],
    usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
    format: 'rgba32float',
    });
    

    const bindGroup = device.createBindGroup({
    layout: pipeline.getBindGroupLayout(0),
    entries: [
    { binding: 0, resource: { buffer: uniformBuffer_f } },
    { binding: 1, resource: { buffer: uniformBuffer_ui } },
    { binding: 2, resource: textures.renderDst.createView() },
    //{ binding: 3, resource: { buffer: jitterBuffer } },
    { binding: 4, resource: { buffer: buffers.attribs } },
    { binding: 5, resource: { buffer: indexBuffer } },
    //{ binding: 6, resource: { buffer: normalsBuffer } },
    { binding: 7, resource: { buffer: materialsBuffer } },
    //{ binding: 8, resource: { buffer: mat_indicesBuffer } },
    { binding: 9, resource: { buffer: light_indicesBuffer } },
    { binding: 10, resource: { buffer: buffers.aabb } },
    { binding: 11, resource: { buffer: buffers.treeIds}},
    { binding: 12, resource: { buffer: buffers.bspTree}},
    { binding: 13, resource: { buffer: buffers.bspPlanes}}
    ],
    });


    animate();
}



function render(device, context, pipeline, textures, bindGroup)
{
    const encoder = device.createCommandEncoder();
    const pass = encoder.beginRenderPass({
    colorAttachments: [
    { view: context.getCurrentTexture().createView(), loadOp: "clear", storeOp: "store" },
    { view: textures.renderSrc.createView(), loadOp: "load", storeOp: "store" }]
    });
    pass.setPipeline(pipeline);
    pass.setBindGroup(0, bindGroup);
    pass.draw(4);
    pass.end();
    encoder.copyTextureToTexture({ texture: textures.renderSrc }, { texture: textures.renderDst },
    [textures.width, textures.height]);
    // Finish the command buffer and immediately submit it.
    device.queue.submit([encoder.finish()]);
}

function set_up_position_buffer(device, vertices)
{
    console.log("vertices = ", vertices);
    const positionsBuffer = device.createBuffer({
        label: 'positions',
        size: vertices.byteLength,
        usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.STORAGE
        });
    device.queue.writeBuffer(positionsBuffer, 0, vertices);
    return positionsBuffer;
}

function set_up_index_buffer(device, indices)
{
    console.log("indices = ", indices);
    const indexBuffer = device.createBuffer({
        label: 'indices',
        size: indices.byteLength,
        usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.STORAGE
        });
    device.queue.writeBuffer(indexBuffer, 0, indices);
    return indexBuffer;
}
function set_up_normal_buffer(device, normals)
{
    console.log("normals = ", normals);
    const normalsBuffer = device.createBuffer({
        label: 'normals',
        size: normals.byteLength,
        usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.STORAGE
        });
    device.queue.writeBuffer(normalsBuffer, 0, normals);
    return normalsBuffer;
}

function set_up_materials_buffer(device, materials)
{
    var materialData = [];
    // Add padding to ensure alignment
    materials.forEach(material => {
    // Color (4 floats, 16 bytes)
    materialData.push(material.color.r, material.color.g, material.color.b, material.color.a);
    // Emission (4 floats, 16 bytes)
    materialData.push(material.emission.r, material.emission.g, material.emission.b, material.emission.a);
    // Specular (4 floats, 16 bytes)
    materialData.push(material.specular.r, material.specular.g, material.specular.b, material.specular.a);
    // Illumination (1 float, needs padding to align to 16 bytes)
    materialData.push(material.illum);  // Illum will be aligned with 4-byte padding
    // Add padding for proper alignment (1 float for padding, 4 bytes)
    materialData.push(0.0,0.0,0.0);  // Add padding to align the next Color struct
  });

    materialData = new Float32Array(materialData);
    console.log("materialData = ", materialData);
    console.log("materialData.length = ", materialData.length);
    const materialsBuffer = device.createBuffer({
        label: 'materials',
        size: materialData.byteLength,
        usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.STORAGE
        });
    device.queue.writeBuffer(materialsBuffer, 0, materialData);
    return materialsBuffer;
}

function set_up_material_indices_buffer(device, mat_indices)
{
    console.log("mat_indices = ", mat_indices);
    const mat_indicesBuffer = device.createBuffer({
        size: mat_indices.byteLength,
        usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.STORAGE
        });
    device.queue.writeBuffer(mat_indicesBuffer, 0, mat_indices);
    return mat_indicesBuffer;
}

function set_up_lifght_indices_buffer(device, light_indices)
{
    console.log("light_indices = ", light_indices);
    const light_indicesBuffer = device.createBuffer({
        size: light_indices.byteLength,
        usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.STORAGE
        });
    device.queue.writeBuffer(light_indicesBuffer, 0, light_indices);
    return light_indicesBuffer;
}



    
    