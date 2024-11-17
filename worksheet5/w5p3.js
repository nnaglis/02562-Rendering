"use strict";

const padding = 0.0;


// Define Triangle class with face indices as vec3u
class Triangle {
    constructor(vertices, faceIndices) {
        this.vertices = vertices; // Array of vec3f
        this.faceIndices = faceIndices; // Array of vec3u
    }
}

// Create the Triangle object
const triangle = new Triangle(
    [
        vec3(-0.2, 0.1, 0.9),
        vec3(0.2, 0.1, 0.9),
        vec3(-0.2, 0.1, -0.1)
    ],
        [0, 1, 2 ,0]
);

    

class Camera {
    eyePos = vec3(0.15, 1.5, 10.0);
    lookat = vec3(0.15, 1.5, 0.0);
    up = vec3(0.0, 1.0, 0.0);
    cam_const = 2.5;
};



// Create an instance of the Camera class
const camera = new Camera();

// Create a variable to store the uniform buffer
var uniforms_f, uniforms_ui;
var uniformBuffer_f, uniformBuffer_ui;

var sphere_shader = 5;
var plane_triangle_shader = 2;
var use_repeat = 1;
var use_linear = 1;
var use_texture = 1;
var pixel_subdivision = 1;
var jitter = new Float32Array(200)


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

    var addressMenu = document.getElementById("addressmode");
    var filterMenu = document.getElementById("filtermode");     

    addEventListener("wheel", (event) => {
        camera.cam_const *= 1.0 + 2.5e-4*event.deltaY;
        uniforms_f[3] = camera.cam_const;
        device.queue.writeBuffer(uniformBuffer_f, 0, uniforms_f);
        console.log("camera.cam_const = " + camera.cam_const);
        animate();
        });

    addressMenu.addEventListener("click", () => {
        uniforms_ui[2] = addressMenu.selectedIndex;
        device.queue.writeBuffer(uniformBuffer_ui, 0, uniforms_ui);
        requestAnimationFrame(animate);
        console.log("addressMenu.selectedIndex = " + addressMenu.selectedIndex);
        });
    filterMenu.addEventListener("click", () => {
        uniforms_ui[3] = filterMenu.selectedIndex;
        device.queue.writeBuffer(uniformBuffer_ui, 0, uniforms_ui);
        requestAnimationFrame(animate);
        console.log("filterMenu.selectedIndex = " + filterMenu.selectedIndex);  
        });

    const useTextureCheckbox = document.getElementById('useTexture');
    
    useTextureCheckbox.addEventListener('change', function() {
        if (useTextureCheckbox.checked)
        {
            use_texture = 1;
        }
        else
        {
            use_texture = 0;
        }
        uniforms_ui[4] = use_texture;
        device.queue.writeBuffer(uniformBuffer_ui, 0, uniforms_ui);
        requestAnimationFrame(animate);
        console.log("use_texture = " + use_texture);
    });

    const dropdown2 = document.getElementById('planeTriangleOptions');

    // Add an event listener for the 'change' event
    dropdown2.addEventListener('change', function() {
        const selectedOption = dropdown2.value;
        if (selectedOption === "Lambertian")
        {
            plane_triangle_shader = 1;
        }
        else if (selectedOption === "Phong")
        {
            plane_triangle_shader = 2;
        }
        else if (selectedOption === "Mirror")
        {
            plane_triangle_shader = 3;
        }
        else
        {
            plane_triangle_shader = 0;
        }
        uniforms_ui[1] = plane_triangle_shader;
        device.queue.writeBuffer(uniformBuffer_ui, 0, uniforms_ui);
        console.log("plane_triangle_shader = " + plane_triangle_shader);
        animate();
    });

    const pixelSubdivisionSlider = document.getElementById('pixelSubdivision');

    pixelSubdivisionSlider.addEventListener('input', function() {
        pixel_subdivision = pixelSubdivisionSlider.value;
        uniforms_ui[5] = pixel_subdivision;
        device.queue.writeBuffer(uniformBuffer_ui, 0, uniforms_ui);
        console.log("pixel_subdivision = " + pixel_subdivision);
        compute_jitters(jitter, 1/canvas.height, pixel_subdivision);
        device.queue.writeBuffer(jitterBuffer, 0, jitter);
        animate();
    });


    function animate()
        {
        render(device, context, pipeline, bindGroup);
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
            targets: [{ format: canvasFormat }]
        }, primitive: {
            topology: "triangle-strip",
        },
    });

    uniformBuffer_f = device.createBuffer({
        size: 48,
        usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST, });

    uniformBuffer_ui = device.createBuffer({
        size: 24,
        usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST, });

        const jitterBuffer = device.createBuffer({
        size: jitter.byteLength,
        usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.STORAGE
        });

    compute_jitters(jitter, 1/canvas.height, pixel_subdivision);

    device.queue.writeBuffer(jitterBuffer, 0, jitter);

    uniforms_f = new Float32Array([
        camera.eyePos[0], camera.eyePos[1], camera.eyePos[2], camera.cam_const,
        camera.lookat[0], camera.lookat[1], camera.lookat[2], aspect,
        camera.up[0], camera.up[1], camera.up[2], padding,
    ]);
    device.queue.writeBuffer(uniformBuffer_f, 0, uniforms_f);

    uniforms_ui = new Uint32Array([
        sphere_shader, plane_triangle_shader, use_repeat, use_linear, use_texture, pixel_subdivision
    ]);
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

    const obj_filename = '../data/objects/teapot.obj';
    const drawingInfo = await readOBJFile(obj_filename, 1, true);

    console.log("drawingInfo = ", drawingInfo);
    
    var positionsBuffer = set_up_position_buffer(device, drawingInfo.vertices);
    var indexBuffer = set_up_index_buffer(device, drawingInfo.indices);

    const texture = await load_texture(device, "../data/grass.jpg");
    const bindGroup = device.createBindGroup({
    layout: pipeline.getBindGroupLayout(0),
    entries: [
    { binding: 0, resource: { buffer: uniformBuffer_f } },
    { binding: 1, resource: { buffer: uniformBuffer_ui } },
    { binding: 2, resource: texture.createView() },
    { binding: 3, resource: { buffer: jitterBuffer } },
    { binding: 4, resource: { buffer: positionsBuffer } },
    { binding: 5, resource: { buffer: indexBuffer } },
    ],
    });


    animate();
}



function render(device, context, pipeline, bindGroup)
    {
        // Create a render pass in a command buffer and submit it 
        let encoder = device.createCommandEncoder();
        let pass = encoder.beginRenderPass({
            colorAttachments: [{
                view: context.getCurrentTexture().createView(), loadOp: "clear",
                storeOp: "store",
            }]
        });
        pass.setPipeline(pipeline);
        pass.setBindGroup(0, bindGroup);
        pass.draw(4);
        pass.end();
        device.queue.submit([encoder.finish()]);
    }

function compute_jitters(jitter, pixelsize, subdivs)
{
    const step = pixelsize/subdivs;
    if(subdivs < 2)
    {
        jitter[0] = 0.0;
        jitter[1] = 0.0;
    }
    else 
    {
    for(var i = 0; i < subdivs; ++i)
        for(var j = 0; j < subdivs; ++j) 
        {
            const idx = (i*subdivs + j)*2;
            jitter[idx] = (Math.random() + j)*step - pixelsize*0.5;
            jitter[idx + 1] = (Math.random() + i)*step - pixelsize*0.5;
        }
    }
}

function set_up_position_buffer(device, vertices)
{
    console.log("vertices = ", vertices);
    const positionsBuffer = device.createBuffer({
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
        size: indices.byteLength,
        usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.STORAGE
        });
    device.queue.writeBuffer(indexBuffer, 0, indices);
    return indexBuffer;
}



    
    