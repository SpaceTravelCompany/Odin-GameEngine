package engine

import "core:math"
import "core:math/linalg"
import "base:intrinsics"
import vk "vendor:vulkan"


//descriptor_pool_size__@@

@rodata descriptor_pool_size__base_uniform_pool : [1]descriptor_pool_size = {{type = .UNIFORM, cnt = 2, binding = 0}}

@rodata descriptor_pool_size__single_sampler_pool : [1]descriptor_pool_size = {{type = .SAMPLER, cnt = 1, binding = 0}}
@rodata descriptor_pool_size__single_uniform_pool : [1]descriptor_pool_size = {{type = .UNIFORM, cnt = 1, binding = 0}}
@rodata descriptor_pool_size__single_storage_pool : [1]descriptor_pool_size = {{type = .STORAGE, cnt = 1, binding = 0}}
