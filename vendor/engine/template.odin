#+private
package engine

import "core:math"
import "core:math/linalg"
import "base:intrinsics"
import vk "vendor:vulkan"

@rodata __singleSamplerPoolSizes : [1]custom_object_DescriptorPoolSize = {{type = .SAMPLER, cnt = 1}}
@rodata __singlePoolBinding : [1]u32 = {0}
@rodata __singleUniformPoolSizes : [1]custom_object_DescriptorPoolSize = {{type = .UNIFORM, cnt = 1}}
@rodata __singleStoragePoolSizes : [1]custom_object_DescriptorPoolSize = {{type = .STORAGE, cnt = 1}}
@rodata __transformUniformPoolSizes : [2]custom_object_DescriptorPoolSize = {{type = .UNIFORM, cnt = 3}, {type = .UNIFORM, cnt = 1}}
@rodata __transformUniformPoolBinding : [2]u32 = {0, 3}
@rodata __imageUniformPoolSizes : [2]custom_object_DescriptorPoolSize = {{type = .UNIFORM, cnt = 3}, {type = .UNIFORM, cnt = 1}}
@rodata __imageUniformPoolBinding : [2]u32 = {0, 3}
@rodata __animateImageUniformPoolSizes : [2]custom_object_DescriptorPoolSize = {{type = .UNIFORM, cnt = 3}, {type = .UNIFORM, cnt = 2}}
@rodata __animateImageUniformPoolBinding : [2]u32 = {0, 3}
@rodata __tileImageUniformPoolSizes : [2]custom_object_DescriptorPoolSize = {{type = .UNIFORM, cnt = 3}, {type = .UNIFORM, cnt = 2}}
@rodata __tileImageUniformPoolBinding : [2]u32 = {0, 3}
