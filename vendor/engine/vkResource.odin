#+private
package engine

import vk "vendor:vulkan"
import "core:mem"
import "base:runtime"
import "core:debug/trace"
import "core:container/intrusive/list"
import "core:math"
import "core:c"

VkSize :: vk.DeviceSize

VkResourceRange :: rawptr


VkDescriptorPoolMem :: struct {pool:vk.DescriptorPool, cnt:u32}

VK_MAX_RESOURCES_FROM_DESCRIPTOR_SET :: 5

VkDescriptorSet :: struct {
    layout: vk.DescriptorSetLayout,
    ///created inside update_descriptor_sets call
    __set: vk.DescriptorSet,
    size: []custom_object_DescriptorPoolSize,
    bindings: []u32,
    __resources: [VK_MAX_RESOURCES_FROM_DESCRIPTOR_SET]VkUnionResource,
};

TextureType :: enum {
    TEX2D,
   // TEX3D,
}
TextureUsage :: enum {
    IMAGE_RESOURCE,
    FRAME_BUFFER,
    __INPUT_ATTACHMENT,
    __TRANSIENT_ATTACHMENT,
    __STORAGE_IMAGE,
}
TextureUsages :: bit_set[TextureUsage]


TextureCreateOption :: struct {
    len:u32,
    width:u32,
    height:u32,
    type:TextureType,
    textureUsage:TextureUsages,
    resourceUsage:ResourceUsage,
    format:TextureFmt,
    samples:u8,
    single:bool,
    useGCPUMem:bool,
}

BufferType :: enum {
    VERTEX,
    INDEX,
    UNIFORM,
    STORAGE,
    __STAGING
}

BufferCreateOption :: struct {
    len:VkSize,
    type:BufferType,
    resourceUsage:ResourceUsage,
    single:bool,
    useGCPUMem:bool,
}


VkUnionResource :: union #no_nil {
    ^VkBufferResource,
    ^VkTextureResource
}
VkBaseResource :: struct {
    data : VkResourceData,
    gUniformIndices : [4]vk.DeviceSize,
    idx:VkResourceRange,//unused uniform buffer
    vkMemBuffer:^VkMemBuffer,
}
VkResourceData :: struct {
    data:[]byte,
    allocator:Maybe(runtime.Allocator),
    is_creating_modifing:bool,
}
VkBufferResource :: struct {
    using _:VkBaseResource,
    option:BufferCreateOption,
    __resource:vk.Buffer,
}
VkTextureResource :: struct {
    using _:VkBaseResource,
    imgView:vk.ImageView,
    sampler:vk.Sampler,
    option:TextureCreateOption,
    __resource:vk.Image,
}

@(require_results) samplesToVkSampleCountFlags :: proc "contextless"(#any_int samples : int) -> vk.SampleCountFlags {
    switch samples {
        case 1: return {._1}
        case 2: return {._2}
        case 4: return {._4}
        case 8: return {._8}
        case 16: return {._16}
        case 32: return {._32}
        case 64: return {._64}
    }
    trace.panic_log("unsupport samples samplesToVkSampleCountFlags : ", samples)
}

@(require_results) TextureTypeToVkImageType :: proc "contextless"(t : TextureType) -> vk.ImageType {
    switch t {
        case .TEX2D:return .D2
    }
    return .D2
}

@(require_results) DescriptorTypeToVkDescriptorType :: proc "contextless"(t : custom_object_DescriptorType) -> vk.DescriptorType {
    switch t {
        case .SAMPLER : return .COMBINED_IMAGE_SAMPLER
        case .UNIFORM : return .UNIFORM_BUFFER
        case .UNIFORM_DYNAMIC : return .UNIFORM_BUFFER_DYNAMIC
        case .STORAGE : return .STORAGE_BUFFER
        case .STORAGE_IMAGE : return .STORAGE_IMAGE
    }
    return .UNIFORM_BUFFER
}