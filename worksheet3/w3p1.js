"use strict";

const padding = 0.0;

class Camera {
    eyePos = vec3(2.0, 1.5, 2.0);
    lookat = vec3(0.0, 0.5, 0.0);
    up = vec3(0.0, 1.0, 0.0);
    cam_const = 1.0;
};

// Create an instance of the Camera class
const camera = new Camera();

// Create a variable to store the uniform buffer
var uniforms_f, uniforms_ui;
var uniformBuffer_f, uniformBuffer_ui;

var sphere_shader = 1;
var plane_triangle_shader = 1;
var use_repeat = 1;
var use_linear = 1;


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

    const dropdown1 = document.getElementById('sphereOptions');

    // Add an event listener for the 'change' event
    dropdown1.addEventListener('change', function() {
        const selectedOption = dropdown1.value;
        if (selectedOption === "Lambertian")
        {
            sphere_shader = 1;
        }
        if (selectedOption === "Phong")
        {
            sphere_shader = 2;
        }
        if (selectedOption === "Mirror")
        {
            sphere_shader = 3;
        }
        else if (selectedOption === "Refraction")
        {
            sphere_shader = 4;
        }
        else if (selectedOption === "Glossy")
        {
            sphere_shader = 5;
        }
        if (selectedOption === "Base")
        {
            sphere_shader = 0;
        }
        uniforms_ui[0] = sphere_shader;
        device.queue.writeBuffer(uniformBuffer_ui, 0, uniforms_ui);
        console.log("sphere_shader = " + sphere_shader);
        animate();
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
        size: 16,
        usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST, });



    uniforms_f = new Float32Array([
        camera.eyePos[0], camera.eyePos[1], camera.eyePos[2], camera.cam_const,
        camera.lookat[0], camera.lookat[1], camera.lookat[2], aspect,
        camera.up[0], camera.up[1], camera.up[2], padding,
    ]);
    device.queue.writeBuffer(uniformBuffer_f, 0, uniforms_f);

    uniforms_ui = new Uint32Array([
        sphere_shader, plane_triangle_shader, use_repeat, use_linear,
    ]);
    device.queue.writeBuffer(uniformBuffer_ui, 0, uniforms_ui);

    //dropdown1.dispatchEvent(new Event('change'));

    const texture = await load_texture(device, "../data/grass.jpg");
    const bindGroup = device.createBindGroup({
    layout: pipeline.getBindGroupLayout(0),
    entries: [
    { binding: 0, resource: { buffer: uniformBuffer_f } },
    { binding: 1, resource: { buffer: uniformBuffer_ui } },
    { binding: 2, resource: texture.createView() },
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



    
    