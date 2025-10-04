#version 450

layout(location = 1) in vec3 inUv;

#extension GL_EXT_debug_printf : enable

void main() {
    float res = (pow(inUv.x, 3) - inUv.y * inUv.z);

    //debugPrintfEXT("res %f\n", res);
    if (res <= 0) discard;

   // debugPrintfEXT("pos %f %f %f\n", inUv.x, inUv.y, inUv.z);
}