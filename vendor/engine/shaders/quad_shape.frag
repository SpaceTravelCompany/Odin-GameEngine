#version 450

layout(location = 0) out vec4 outColor;

layout(binding = 0) uniform UniformBufferObject0 {
    vec4 color;
} cor;


#extension GL_EXT_debug_printf : enable

void main() {
    //debugPrintfEXT("color %f %f %f %f\n", cor.color.x, cor.color.y, cor.color.z, cor.color.w);
    outColor = cor.color;
}