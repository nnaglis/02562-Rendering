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

    function animate()
        {
        uniforms[3] = camera.cam_const;
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
        size: 48,
        usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST, });
    const bindGroup = device.createBindGroup({ layout: pipeline.getBindGroupLayout(0), entries: [{
        binding: 0,
        resource: { buffer: uniformBuffer } }],
    });


    uniforms = new Float32Array([
        camera.eyePos[0], camera.eyePos[1], camera.eyePos[2], camera.cam_const,
        camera.lookat[0], camera.lookat[1], camera.lookat[2], aspect,
        camera.up[0], camera.up[1], camera.up[2], padding
    ]);
    device.queue.writeBuffer(uniformBuffer, 0, uniforms);

    console.log("uniforms = " + uniforms);


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



    
    