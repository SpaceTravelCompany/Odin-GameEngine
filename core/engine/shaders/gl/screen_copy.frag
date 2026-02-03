#version 460

layout(input_attachment_index = 0, set = 0, binding = 0) uniform subpassInput computeResult;

layout(location = 0) out vec4 outColor;

void main() {
	vec4 fromCompute = subpassLoad(computeResult);
	// Example: use as-is or blend with scene
	outColor = fromCompute;
}