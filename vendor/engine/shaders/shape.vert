#version 450

layout(set = 0, binding = 0) uniform UniformBufferObject0 {
    mat4 model;
} model;
layout(set = 0, binding = 1) uniform UniformBufferObject1 {
    mat4 view;
} view;
layout(set = 0, binding = 2) uniform UniformBufferObject2 {
    mat4 proj;
} proj;


#extension GL_EXT_debug_printf : enable
layout(location = 0) in vec2 inPosition;


layout(location = 1) in vec3 inUv;
layout(location = 1) out vec3 outUv;

void main() {
    gl_Position = proj.proj * view.view * model.model * vec4(inPosition, 0.0, 1.0);
    // if (inPosition.y != 0.0) {
    //     debugPrintfEXT("pos %f %f uv %f %f %f\n", inPosition.x,inPosition.y, inUv.x,inUv.y,inUv.z);
    // }
    //debugPrintfEXT("pos %f %f uv %f %f %f\n", inPosition.x,inPosition.y, inUv.x,inUv.y,inUv.z);
    outUv = inUv;
}