package engine

import "core:math"
import "core:math/linalg"
import "base:intrinsics"
import vk "vendor:vulkan"


//descriptor_set_binding__@@
//descriptor_pool_size__@@


@rodata descriptor_pool_size__single_sampler_pool : [1]descriptor_pool_size = {{type = .SAMPLER, cnt = 1}}
@rodata descriptor_set_binding__single_pool : [1]u32 = {0}
@rodata descriptor_pool_size__single_uniform_pool : [1]descriptor_pool_size = {{type = .UNIFORM, cnt = 1}}
@rodata descriptor_pool_size__single_storage_pool : [1]descriptor_pool_size = {{type = .STORAGE, cnt = 1}}
@rodata descriptor_pool_size__transform_uniform_pool : [2]descriptor_pool_size = {{type = .UNIFORM, cnt = 3}, {type = .UNIFORM, cnt = 1}}
@rodata descriptor_set_binding__transform_uniform_pool : [2]u32 = {0, 3}
@rodata descriptor_pool_size__image_uniform_pool : [2]descriptor_pool_size = {{type = .UNIFORM, cnt = 3}, {type = .UNIFORM, cnt = 1}}
@rodata descriptor_set_binding__image_uniform_pool : [2]u32 = {0, 3}
@rodata descriptor_pool_size__animate_image_uniform_pool : [2]descriptor_pool_size = {{type = .UNIFORM, cnt = 3}, {type = .UNIFORM, cnt = 2}}
@rodata descriptor_set_binding__animate_image_uniform_pool : [2]u32 = {0, 3}
@rodata descriptor_pool_size__tile_image_uniform_pool : [2]descriptor_pool_size = {{type = .UNIFORM, cnt = 3}, {type = .UNIFORM, cnt = 2}}
@rodata descriptor_set_binding__tile_image_uniform_pool : [2]u32 = {0, 3}