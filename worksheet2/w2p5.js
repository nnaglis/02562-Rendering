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
var uniforms;

var sphere_shader = 1;
var plane_triangle_shader = 1;




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
        camera.cam_const *= 1.0 + 2.5e-4*event.deltaY;
        requestAnimationFrame(animate);
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
        if (selectedOption === "Base")
        {
            sphere_shader = 0;
        }
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
        console.log("plane_triangle_shader = " + plane_triangle_shader);
        animate();
    });

    function animate()
        {
        uniforms[3] = camera.cam_const;
        uniforms[12] = sphere_shader;
        uniforms[13] = plane_triangle_shader;
        device.queue.writeBuffer(uniformBuffer, 0, uniforms);
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

    const uniformBuffer = device.createBuffer({
        size: 64,
        usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST, });
    const bindGroup = device.createBindGroup({ layout: pipeline.getBindGroupLayout(0), entries: [{
        binding: 0,
        resource: { buffer: uniformBuffer } }],
    });


    uniforms = new Float32Array([
        camera.eyePos[0], camera.eyePos[1], camera.eyePos[2], camera.cam_const,
        camera.lookat[0], camera.lookat[1], camera.lookat[2], aspect,
        camera.up[0], camera.up[1], camera.up[2], padding,
        sphere_shader, plane_triangle_shader, padding, padding
    ]);
    device.queue.writeBuffer(uniformBuffer, 0, uniforms);

    console.log("uniforms = " + uniforms);


    dropdown1.dispatchEvent(new Event('change'));

     // Insert render pass commands here
    render(device, context, pipeline, bindGroup); 
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



    
    