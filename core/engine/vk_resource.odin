#+private
package engine

import vk "vendor:vulkan"
import "core:mem"
import "base:runtime"
import "core:debug/trace"
import "core:container/intrusive/list"
import "core:math"
import "core:c"



@(require_results) samples_to_vk_sample_count_flags :: proc "contextless"(#any_int samples : int) -> vk.SampleCountFlags {
    switch samples {
        case 1: return {._1}
        case 2: return {._2}
        case 4: return {._4}
        case 8: return {._8}
        case 16: return {._16}
        case 32: return {._32}
        case 64: return {._64}
    }
    trace.panic_log("unsupport samples samples_to_vk_sample_count_flags : ", samples)
}

@(require_results) texture_type_to_vk_image_type :: proc "contextless"(t : texture_type) -> vk.ImageType {
    switch t {
        case .TEX2D:return .D2
    }
    return .D2
}

@(require_results) descriptor_type_to_vk_descriptor_type :: proc "contextless"(t : descriptor_type) -> vk.DescriptorType {
    switch t {
        case .SAMPLER : return .COMBINED_IMAGE_SAMPLER
        case .UNIFORM : return .UNIFORM_BUFFER
        case .UNIFORM_DYNAMIC : return .UNIFORM_BUFFER_DYNAMIC
        case .STORAGE : return .STORAGE_BUFFER
        case .STORAGE_IMAGE : return .STORAGE_IMAGE
    }
    return .UNIFORM_BUFFER
}