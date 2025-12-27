package sys

import "core:math"
import "core:math/linalg"
import "base:intrinsics"
import vk "vendor:vulkan"

@rodata __single_sampler_pool_sizes : [1]descriptor_pool_size = {{type = .SAMPLER, cnt = 1}}
@rodata __single_pool_binding : [1]u32 = {0}
@rodata __single_uniform_pool_sizes : [1]descriptor_pool_size = {{type = .UNIFORM, cnt = 1}}
@rodata __single_storage_pool_sizes : [1]descriptor_pool_size = {{type = .STORAGE, cnt = 1}}
@rodata __transform_uniform_pool_sizes : [2]descriptor_pool_size = {{type = .UNIFORM, cnt = 3}, {type = .UNIFORM, cnt = 1}}
@rodata __transform_uniform_pool_binding : [2]u32 = {0, 3}
@rodata __image_uniform_pool_sizes : [2]descriptor_pool_size = {{type = .UNIFORM, cnt = 3}, {type = .UNIFORM, cnt = 1}}
@rodata __image_uniform_pool_binding : [2]u32 = {0, 3}
@rodata __animate_image_uniform_pool_sizes : [2]descriptor_pool_size = {{type = .UNIFORM, cnt = 3}, {type = .UNIFORM, cnt = 2}}
@rodata __animate_image_uniform_pool_binding : [2]u32 = {0, 3}
@rodata __tile_image_uniform_pool_sizes : [2]descriptor_pool_size = {{type = .UNIFORM, cnt = 3}, {type = .UNIFORM, cnt = 2}}
@rodata __tile_image_uniform_pool_binding : [2]u32 = {0, 3}