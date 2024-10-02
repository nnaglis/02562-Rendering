"use strict";

const padding = 0.0;

class Camera {
    eyePos = vec3(2.0, 1.5, 2.0);
    lookat = vec3(0.0, 0.5, 0.0);
    up = vec3(0.0, 1.0, 0.0);
    constant = 1.0;
};

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

    

    const wgsl = device.createShaderModule({
        code: document.getElementById("wgsl").text
    });

    

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

    // Create an instance of the Camera class
    const camera = new Camera();

    var uniforms = new Float32Array([
        camera.eyePos[0], camera.eyePos[1], camera.eyePos[2], padding,
        camera.lookat[0], camera.lookat[1], camera.lookat[2], padding,
        camera.up[0], camera.up[1], camera.up[2], padding,
        camera.constant, padding, padding, padding]);
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
