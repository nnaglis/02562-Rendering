"use strict";
var cam_const;
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
        size: 8, // number of bytes
        usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST, });
        const bindGroup = device.createBindGroup({ layout: pipeline.getBindGroupLayout(0), entries: [{
        binding: 0,
        resource: { buffer: uniformBuffer } }],
        });

    const aspect = canvas.width/canvas.height;
    var cam_const = 0;
    var uniforms = new Float32Array([aspect, cam_const]);
    device.queue.writeBuffer(uniformBuffer, 0, uniforms);


     // Insert render pass commands here
    render(device, context, pipeline, bindGroup);

    // addEventListener("mouse", (event) => { cam_const *= 1.0 + 2.5e-4*event.deltaY; requestAnimationFrame(tick);
    // });
    // function tick()
    // {
    
    // uniforms[1] = cam_const;
    // device.queue.writeBuffer(uniformBuffer, 0, uniforms);
    // console.log("uniforms = " + uniforms);
    // render(device, context, pipeline, bindGroup);
    // } tick();

    
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
