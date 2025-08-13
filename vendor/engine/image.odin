package engine

import "core:math"
import "core:mem"
import "core:slice"
import "core:sync"
import "core:debug/trace"
import "core:math/linalg"
import "base:intrinsics"
import "base:runtime"
import vk "vendor:vulkan"


ImageCenterPtPos :: enum {
    Center,
    Left,
    Right,
    TopLeft,
    Top,
    TopRight,
    BottomLeft,
    Bottom,
    BottomRight,
}

Texture :: struct {
    texture:VkTextureResource,
    set:VkDescriptorSet,
    sampler: vk.Sampler,
    checkInit: mem.ICheckInit,
}

TextureArray :: struct {
    using _: Texture,
}

TileTextureArray :: struct {
    using _: Texture,
}

Image :: struct {
    using _:IObject,
    src: ^Texture,
}

AnimateImage :: struct {
    using _:ianimate_object,
    src: ^TextureArray,
}

TileImage :: struct {
    using object:IObject,
    tileUniform:VkBufferResource,
    tileIdx:u32,
    src: ^TileTextureArray,
}

IsAnyImageType :: #force_inline proc "contextless" ($ANY_IMAGE:typeid) -> bool {
    return intrinsics.type_is_subtype_of(ANY_IMAGE, IObject) && intrinsics.type_has_field(ANY_IMAGE, "src") && 
    (intrinsics.type_field_type(ANY_IMAGE, "src") == Texture ||
    intrinsics.type_field_type(ANY_IMAGE, "src") == TextureArray ||
    intrinsics.type_field_type(ANY_IMAGE, "src") == TileTextureArray)
}

@private ImageVTable :IObjectVTable = IObjectVTable {
    Draw = auto_cast _Super_Image_Draw,
    Deinit = auto_cast _Super_Image_Deinit,
}

Image_Init :: proc(self:^Image, $actualType:typeid, src:^Texture, pos:linalg.Point3DF,
camera:^Camera, projection:^Projection,
rotation:f32 = 0.0, scale:linalg.PointF = {1,1}, colorTransform:^ColorTransform = nil, pivot:linalg.PointF = {0.0, 0.0}, vtable:^IObjectVTable = nil) where intrinsics.type_is_subtype_of(actualType, Image) {
    self.src = src
        
    self.set.bindings = __transformUniformPoolBinding[:]
    self.set.size = __transformUniformPoolSizes[:]
    self.set.layout = vkTexDescriptorSetLayout

    self.vtable = vtable == nil ? &ImageVTable : vtable
    if self.vtable.Draw == nil do self.vtable.Draw = auto_cast _Super_Image_Draw
    if self.vtable.Deinit == nil do self.vtable.Deinit = auto_cast _Super_Image_Deinit

    if self.vtable.GetUniformResources == nil do self.vtable.GetUniformResources = auto_cast GetUniformResources_Default

    IObject_Init(self, actualType, pos, rotation, scale, camera, projection, colorTransform, pivot)
}

Image_Init2 :: proc(self:^Image, $actualType:typeid, src:^Texture,
camera:^Camera, projection:^Projection,
colorTransform:^ColorTransform = nil, vtable:^IObjectVTable = nil) where intrinsics.type_is_subtype_of(actualType, Image) {
    self.src = src
        
    self.set.bindings = __transformUniformPoolBinding[:]
    self.set.size = __transformUniformPoolSizes[:]
    self.set.layout = vkTexDescriptorSetLayout

    self.vtable = vtable == nil ? &ImageVTable : vtable
    if self.vtable.Draw == nil do self.vtable.Draw = auto_cast _Super_Image_Draw
    if self.vtable.Deinit == nil do self.vtable.Deinit = auto_cast _Super_Image_Deinit

    if self.vtable.GetUniformResources == nil do self.vtable.GetUniformResources = auto_cast GetUniformResources_Default

    IObject_Init2(self, actualType, camera, projection, colorTransform)
}

_Super_Image_Deinit :: proc(self:^Image) {
    _Super_IObject_Deinit(auto_cast self)
}

Image_GetTexture :: #force_inline proc "contextless" (self:^Image) -> ^Texture {
    return self.src
}
Image_GetCamera :: proc "contextless" (self:^Image) -> ^Camera {
    return IObject_GetCamera(self)
}
Image_GetProjection :: proc "contextless" (self:^Image) -> ^Projection {
    return IObject_GetProjection(self)
}
Image_GetColorTransform :: proc "contextless" (self:^Image) -> ^ColorTransform {
    return IObject_GetColorTransform(self)
}
Image_UpdateTransform :: #force_inline proc(self:^Image, pos:linalg.Point3DF, rotation:f32 = 0.0, scale:linalg.PointF = {1,1}, pivot:linalg.PointF = {0.0,0.0}) {
    IObject_UpdateTransform(self, pos, rotation, scale, pivot)
}
Image_UpdateTransformMatrixRaw :: #force_inline proc(self:^Image, _mat:linalg.Matrix) {
    IObject_UpdateTransformMatrixRaw(self, _mat)
}
Image_UpdateCamera :: #force_inline proc(self:^Image, camera:^Camera) {
    IObject_UpdateCamera(self, camera)
}
Image_UpdateProjection :: #force_inline proc(self:^Image, projection:^Projection) {
    IObject_UpdateProjection(self, projection)
}
Image_UpdateTexture :: #force_inline proc "contextless" (self:^Image, src:^Texture) {
    self.src = src
}
Image_ChangeColorTransform :: #force_inline proc(self:^Image, colorTransform:^ColorTransform) {
    IObject_ChangeColorTransform(self, colorTransform)
}

_Super_Image_Draw :: proc (self:^Image, cmd:vk.CommandBuffer) {
    mem.ICheckInit_Check(&self.checkInit)
    mem.ICheckInit_Check(&self.src.checkInit)

   _Image_BindingSetsAndDraw(cmd, self.set, self.src.set)
}

_Image_BindingSetsAndDraw :: proc "contextless" (cmd:vk.CommandBuffer, imageSet:VkDescriptorSet, textureSet:VkDescriptorSet) {
     vk.CmdBindPipeline(cmd, .GRAPHICS, vkTexPipeline)
    vk.CmdBindDescriptorSets(cmd, .GRAPHICS, vkTexPipelineLayout, 0, 2, 
        &([]vk.DescriptorSet{imageSet.__set, textureSet.__set})[0], 0, nil)

    vk.CmdDraw(cmd, 6, 1, 0, 0)
}


@private AnimateImageVTable :IAnimateObjectVTable = IAnimateObjectVTable {
    Draw = auto_cast _Super_AnimateImage_Draw,
    Deinit = auto_cast _Super_AnimateImage_Deinit,
    get_frame_cnt = auto_cast _Super_AnimateImage_get_frame_cnt,
}

AnimateImage_Init :: proc(self:^AnimateImage, $actualType:typeid, src:^TextureArray, pos:linalg.Point3DF, rotation:f32, scale:linalg.PointF = {1,1}, 
camera:^Camera, projection:^Projection, colorTransform:^ColorTransform = nil, pivot:linalg.PointF = {0.0, 0.0}, vtable:^IAnimateObjectVTable = nil) where intrinsics.type_is_subtype_of(actualType, AnimateImage) {
    self.src = src
    
    self.set.bindings = __animateImageUniformPoolBinding[:]
    self.set.size = __animateImageUniformPoolSizes[:]
    self.set.layout = vkAnimateTexDescriptorSetLayout

    self.vtable = auto_cast (vtable == nil ? &AnimateImageVTable : vtable)
    if self.vtable.Draw == nil do self.vtable.Draw = auto_cast _Super_AnimateImage_Draw
    if self.vtable.Deinit == nil do self.vtable.Deinit = auto_cast _Super_AnimateImage_Deinit
    if ((^IAnimateObjectVTable)(self.vtable)).get_frame_cnt == nil do ((^IAnimateObjectVTable)(self.vtable)).get_frame_cnt = auto_cast _Super_AnimateImage_get_frame_cnt

    if self.vtable.GetUniformResources == nil do self.vtable.GetUniformResources = auto_cast GetUniformResources_AnimateImage

    IObject_Init(self, actualType, pos, rotation, scale, camera, projection, colorTransform, pivot)
}

AnimateImage_Init2 :: proc(self:^AnimateImage, $actualType:typeid, src:^TextureArray,
camera:^Camera, projection:^Projection, colorTransform:^ColorTransform = nil, vtable:^IAnimateObjectVTable = nil) where intrinsics.type_is_subtype_of(actualType, AnimateImage) {
    self.src = src
    
    self.set.bindings = __animateImageUniformPoolBinding[:]
    self.set.size = __animateImageUniformPoolSizes[:]
    self.set.layout = vkAnimateTexDescriptorSetLayout

    self.vtable = auto_cast (vtable == nil ? &AnimateImageVTable : vtable)
    if self.vtable.Draw == nil do self.vtable.Draw = auto_cast _Super_AnimateImage_Draw
    if self.vtable.Deinit == nil do self.vtable.Deinit = auto_cast _Super_AnimateImage_Deinit
    if ((^IAnimateObjectVTable)(self.vtable)).get_frame_cnt == nil do ((^IAnimateObjectVTable)(self.vtable)).get_frame_cnt = auto_cast _Super_AnimateImage_get_frame_cnt

    if self.vtable.GetUniformResources == nil do self.vtable.GetUniformResources = auto_cast GetUniformResources_AnimateImage

    IObject_Init2(self, actualType, camera, projection, colorTransform)
}   

_Super_AnimateImage_Deinit :: proc(self:^AnimateImage) {
     _Super_IObject_Deinit(auto_cast self)
}


AnimateImage_get_frame_cnt :: _Super_AnimateImage_get_frame_cnt

_Super_AnimateImage_get_frame_cnt :: proc "contextless" (self:^AnimateImage) -> u32 {
    return self.src.texture.option.len
}

AnimateImage_GetTextureArray :: #force_inline proc "contextless" (self:^AnimateImage) -> ^TextureArray {
    return self.src
}
AnimateImage_GetCamera :: proc "contextless" (self:^AnimateImage) -> ^Camera {
    return self.camera
}
AnimateImage_GetProjection :: proc "contextless" (self:^AnimateImage) -> ^Projection {
    return self.projection
}
AnimateImage_GetColorTransform :: proc "contextless" (self:^AnimateImage) -> ^ColorTransform {
    return self.colorTransform
}
AnimateImage_UpdateTransform :: #force_inline proc(self:^AnimateImage, pos:linalg.Point3DF, rotation:f32, scale:linalg.PointF = {1,1}, pivot:linalg.PointF = {0.0,0.0}) {
    IObject_UpdateTransform(self, pos, rotation, scale, pivot)
}
AnimateImage_UpdateTransformMatrixRaw :: #force_inline proc(self:^AnimateImage, _mat:linalg.Matrix) {
    IObject_UpdateTransformMatrixRaw(self, _mat)
}
AnimateImage_ChangeColorTransform :: #force_inline proc(self:^AnimateImage, colorTransform:^ColorTransform) {
    IObject_ChangeColorTransform(self, colorTransform)
}
AnimateImage_UpdateCamera :: #force_inline proc(self:^AnimateImage, camera:^Camera) {
    IObject_UpdateCamera(self, camera)
}
AnimateImage_UpdateTextureArray :: #force_inline proc "contextless" (self:^AnimateImage, src:^TextureArray) {
    self.src = src
}
AnimateImage_UpdateProjection :: #force_inline proc(self:^AnimateImage, projection:^Projection) {
    IObject_UpdateProjection(self, projection)
}
_Super_AnimateImage_Draw :: proc (self:^AnimateImage, cmd:vk.CommandBuffer) {
    mem.ICheckInit_Check(&self.checkInit)
    mem.ICheckInit_Check(&self.src.checkInit)

    vk.CmdBindPipeline(cmd, .GRAPHICS, vkAnimateTexPipeline)
    vk.CmdBindDescriptorSets(cmd, .GRAPHICS, vkAnimateTexPipelineLayout, 0, 2, 
        &([]vk.DescriptorSet{self.set.__set, self.src.set.__set})[0], 0, nil)

    vk.CmdDraw(cmd, 6, 1, 0, 0)
}

@private TileImageVTable :IObjectVTable = IObjectVTable {
    Draw = auto_cast _Super_TileImage_Draw,
    Deinit = auto_cast _Super_TileImage_Deinit,
}

TileImage_Init :: proc(self:^TileImage, $actualType:typeid, src:^TileTextureArray, pos:linalg.Point3DF, rotation:f32, scale:linalg.PointF = {1,1}, 
camera:^Camera, projection:^Projection, colorTransform:^ColorTransform = nil, pivot:linalg.PointF = {0, 0}, vtable:^IObjectVTable = nil) where intrinsics.type_is_subtype_of(actualType, TileImage) {
    self.src = src

    self.set.bindings = __tileImageUniformPoolBinding[:]
    self.set.size = __tileImageUniformPoolSizes[:]
    self.set.layout = vkAnimateTexDescriptorSetLayout

    self.vtable = vtable == nil ? &TileImageVTable : vtable
    if self.vtable.Draw == nil do self.vtable.Draw = auto_cast _Super_TileImage_Draw
    if self.vtable.Deinit == nil do self.vtable.Deinit = auto_cast _Super_TileImage_Deinit

    if self.vtable.GetUniformResources == nil do self.vtable.GetUniformResources = auto_cast GetUniformResources_TileImage


    VkBufferResource_CreateBuffer(&self.tileUniform, {
        len = size_of(u32),
        type = .UNIFORM,
        resourceUsage = .CPU,
    }, mem.ptr_to_bytes(&self.tileIdx), true)

    IObject_Init(self, actualType, pos, rotation, scale, camera, projection, colorTransform, pivot)
}

TileImage_Init2 :: proc(self:^TileImage, $actualType:typeid, src:^TileTextureArray,
camera:^Camera, projection:^Projection, colorTransform:^ColorTransform = nil, vtable:^IObjectVTable = nil) where intrinsics.type_is_subtype_of(actualType, TileImage) {
    self.src = src

    self.set.bindings = __tileImageUniformPoolBinding[:]
    self.set.size = __tileImageUniformPoolSizes[:]
    self.set.layout = vkAnimateTexDescriptorSetLayout

    self.vtable = vtable == nil ? &TileImageVTable : vtable
    if self.vtable.Draw == nil do self.vtable.Draw = auto_cast _Super_TileImage_Draw
    if self.vtable.Deinit == nil do self.vtable.Deinit = auto_cast _Super_TileImage_Deinit

    if self.vtable.GetUniformResources == nil do self.vtable.GetUniformResources = auto_cast GetUniformResources_TileImage

    IObject_Init2(self, actualType, camera, projection, colorTransform)
}   

_Super_TileImage_Deinit :: proc(self:^TileImage) {
    VkBufferResource_Deinit(&self.tileUniform)
    _Super_IObject_Deinit(auto_cast self)
}

TileImage_GetTileTextureArray :: #force_inline proc "contextless" (self:^TileImage) -> ^TileTextureArray {
    return self.src
}
TileImage_UpdateTileTextureArray :: #force_inline proc "contextless" (self:^TileImage, src:^TileTextureArray) {
    self.src = src
}
TileImage_UpdateTransform :: #force_inline proc(self:^TileImage, pos:linalg.Point3DF, rotation:f32, scale:linalg.PointF = {1,1}, pivot:linalg.PointF = {0.0, 0.0}) {
    IObject_UpdateTransform(self, pos, rotation, scale, pivot)
}
TileImage_ChangeColorTransform :: #force_inline proc(self:^TileImage, colorTransform:^ColorTransform) {
    IObject_ChangeColorTransform(self, colorTransform)
}
TileImage_UpdateCamera :: #force_inline proc(self:^TileImage, camera:^Camera) {
    IObject_UpdateCamera(self, camera)
}
TileImage_UpdateProjection :: #force_inline proc(self:^TileImage, projection:^Projection) {
    IObject_UpdateProjection(self, projection)
}
TileImage_GetCamera :: proc "contextless" (self:^TileImage) -> ^Camera {
    return IObject_GetCamera(self)
}
TileImage_GetProjection :: proc "contextless" (self:^TileImage) -> ^Projection {
    return IObject_GetProjection(self)
}
TileImage_GetColorTransform :: proc "contextless" (self:^TileImage) -> ^ColorTransform {
    return IObject_GetColorTransform(self)
}
TileImage_UpdateTransformMatrixRaw :: #force_inline proc(self:^TileImage, _mat:linalg.Matrix) {
    IObject_UpdateTransformMatrixRaw(self, _mat)
}

TileImage_UpdateIdx :: proc(self:^TileImage, idx:u32) {
    mem.ICheckInit_Check(&self.checkInit)
    self.tileIdx = idx

    VkBufferResource_CopyUpdate(&self.tileUniform, &self.tileIdx)
}

_Super_TileImage_Draw :: proc (self:^TileImage, cmd:vk.CommandBuffer) {
    mem.ICheckInit_Check(&self.checkInit)
    mem.ICheckInit_Check(&self.src.checkInit)

    vk.CmdBindPipeline(cmd, .GRAPHICS, vkAnimateTexPipeline)
    vk.CmdBindDescriptorSets(cmd, .GRAPHICS, vkAnimateTexPipelineLayout, 0, 2, 
        &([]vk.DescriptorSet{self.set.__set, self.src.set.__set})[0], 0, nil)

    vk.CmdDraw(cmd, 6, 1, 0, 0)
}


Texture_Init :: proc(self:^Texture, #any_int width:int, #any_int height:int, pixels:[]byte, sampler:vk.Sampler = 0, resourceUsage:ResourceUsage = .GPU, inPixelFmt:color_fmt = .RGBA) {
    mem.ICheckInit_Init(&self.checkInit)
    self.sampler = sampler == 0 ? vkLinearSampler : sampler
    self.set.bindings = __singlePoolBinding[:]
    self.set.size = __singleSamplerPoolSizes[:]
    self.set.layout = vkTexDescriptorSetLayout2
    self.set.__set = 0

    allocPixels := mem.make_non_zeroed_slice([]byte, width * height * 4, engineDefAllocator)
    ColorFmtConvertDefault(pixels, allocPixels, inPixelFmt)
   
    VkBufferResource_CreateTexture(&self.texture, {
        width = auto_cast width,
        height = auto_cast height,
        useGCPUMem = false,
        format = .DefaultColor,
        samples = 1,
        len = 1,
        textureUsage = {.IMAGE_RESOURCE},
        type = .TEX2D,
        resourceUsage = resourceUsage,
        single = false,
    }, self.sampler, allocPixels, false, engineDefAllocator)

    self.set.__resources = mem.make_non_zeroed_slice([]VkUnionResource, 1, vkTempArenaAllocator)
    self.set.__resources[0] = &self.texture
    VkUpdateDescriptorSets(mem.slice_ptr(&self.set, 1))
}

Texture_InitGrey :: proc(self:^Texture, #any_int width:int, #any_int height:int, pixels:[]byte, sampler:vk.Sampler = 0, resourceUsage:ResourceUsage = .GPU) {
    mem.ICheckInit_Init(&self.checkInit)
    self.sampler = sampler == 0 ? vkLinearSampler : sampler
    self.set.bindings = __singlePoolBinding[:]
    self.set.size = __singleSamplerPoolSizes[:]
    self.set.layout = vkTexDescriptorSetLayout2
    self.set.__set = 0

    allocPixels := mem.make_non_zeroed_slice([]byte, width * height, engineDefAllocator)
    mem.copy_non_overlapping(&allocPixels[0], &pixels[0], len(pixels))
   
    VkBufferResource_CreateTexture(&self.texture, {
        width = auto_cast width,
        height = auto_cast height,
        useGCPUMem = false,
        format = .R8Unorm,
        samples = 1,
        len = 1,
        textureUsage = {.IMAGE_RESOURCE},
        type = .TEX2D,
        resourceUsage = resourceUsage,
        single = false,
    }, self.sampler, allocPixels, false, engineDefAllocator)

    self.set.__resources = mem.make_non_zeroed_slice([]VkUnionResource, 1, vkTempArenaAllocator)
    self.set.__resources[0] = &self.texture
    VkUpdateDescriptorSets(mem.slice_ptr(&self.set, 1))
}


//sampler nil default //TODO (xfitgd)
// Texture_InitR8 :: proc(self:^Texture, #any_int width:int, #any_int height:int) {
//     mem.ICheckInit_Init(&self.checkInit)
//     self.sampler = 0
//     self.set.bindings = nil
//     self.set.size = nil
//     self.set.layout = 0
//     self.set.__set = 0

//     VkBufferResource_CreateTexture(&self.texture, {
//         width = auto_cast width,
//         height = auto_cast height,
//         useGCPUMem = false,
//         format = .R8Unorm,
//         samples = 1,
//         len = 1,
//         textureUsage = {.FRAME_BUFFER, .__INPUT_ATTACHMENT},
//         type = .TEX2D,
//         resourceUsage = .GPU,
//         single = true,
//     }, self.sampler, nil)
// }


@private Texture_InitDepthStencil :: proc(self:^Texture, #any_int width:int, #any_int height:int) {
    mem.ICheckInit_Init(&self.checkInit)
    self.sampler = 0
    self.set.bindings = nil
    self.set.size = nil
    self.set.layout = 0
    self.set.__set = 0

    VkBufferResource_CreateTexture(&self.texture, {
        width = auto_cast width,
        height = auto_cast height,
        useGCPUMem = false,
        format = .DefaultDepth,
        samples = auto_cast vkMSAACount,
        len = 1,
        textureUsage = {.FRAME_BUFFER},
        type = .TEX2D,
        single = true,
        resourceUsage = .GPU
    }, self.sampler, nil)
}

@private Texture_InitMSAA :: proc(self:^Texture, #any_int width:int, #any_int height:int) {
    mem.ICheckInit_Init(&self.checkInit)
    self.sampler = 0
    self.set.bindings = nil
    self.set.size = nil
    self.set.layout = 0
    self.set.__set = 0

    VkBufferResource_CreateTexture(&self.texture, {
        width = auto_cast width,
        height = auto_cast height,
        useGCPUMem = false,
        format = .DefaultColor,
        samples = auto_cast vkMSAACount,
        len = 1,
        textureUsage = {.FRAME_BUFFER,.__TRANSIENT_ATTACHMENT},
        type = .TEX2D,
        single = true,
        resourceUsage = .GPU
    }, self.sampler, nil)
}

Texture_Deinit :: proc(self:^Texture) {
    mem.ICheckInit_Deinit(&self.checkInit)
    VkBufferResource_Deinit(&self.texture)
}

Texture_Width :: #force_inline proc "contextless" (self:^Texture) -> int {
    return auto_cast self.texture.option.width
}
Texture_Height :: #force_inline proc "contextless" (self:^Texture) -> int {
    return auto_cast self.texture.option.height
}

GetDefaultLinearSampler :: #force_inline proc "contextless" () -> vk.Sampler {
    return vkLinearSampler
}
GetDefaultNearestSampler :: #force_inline proc "contextless" () -> vk.Sampler {
    return vkNearestSampler
}

Texture_UpdateSampler :: #force_inline proc "contextless" (self:^Texture, sampler:vk.Sampler) {
    self.sampler = sampler
}
Texture_GetSampler :: #force_inline proc "contextless" (self:^Texture) -> vk.Sampler {
    return self.sampler
}

TextureArray_Init :: proc(self:^TextureArray, #any_int width:int, #any_int height:int, #any_int count:int, pixels:[]byte, sampler:vk.Sampler = 0, inPixelFmt:color_fmt = .RGBA) {
    mem.ICheckInit_Init(&self.checkInit)
    self.sampler = sampler == 0 ? vkLinearSampler : sampler
    self.set.bindings = __singlePoolBinding[:]
    self.set.size = __singleSamplerPoolSizes[:]
    self.set.layout = vkTexDescriptorSetLayout2
    self.set.__set = 0

    allocPixels := mem.make_non_zeroed_slice([]byte, count * width * height * 4, engineDefAllocator)
    ColorFmtConvertDefault(pixels, allocPixels, inPixelFmt)

    VkBufferResource_CreateTexture(&self.texture, {
        width = auto_cast width,
        height = auto_cast height,
        useGCPUMem = false,
        format = .DefaultColor,
        samples = 1,
        len = auto_cast count,
        textureUsage = {.IMAGE_RESOURCE},
        type = .TEX2D,
        resourceUsage = .GPU,
    }, self.sampler, allocPixels, false, engineDefAllocator)

    self.set.__resources = mem.make_non_zeroed_slice([]VkUnionResource, 1, vkTempArenaAllocator)
    self.set.__resources[0] = &self.texture
    VkUpdateDescriptorSets(mem.slice_ptr(&self.set, 1))
}

TextureArray_Deinit :: #force_inline proc(self:^TextureArray) {
    mem.ICheckInit_Deinit(&self.checkInit)
    VkBufferResource_Deinit(&self.texture)
}
TextureArray_Width :: #force_inline proc "contextless" (self:^TextureArray) -> int {
    return auto_cast self.texture.option.width
}
TextureArray_Height :: #force_inline proc "contextless" (self:^TextureArray) -> int {
    return auto_cast self.texture.option.height
}
TextureArray_Count :: #force_inline proc "contextless" (self:^TextureArray) -> int {
    return auto_cast self.texture.option.len
}

ColorFmtConvertDefault :: proc "contextless" (pixels:[]byte, out:[]byte, inPixelFmt:color_fmt = .RGBA) {
    defcol := default_color_fmt()
    if defcol == inPixelFmt {
        mem.copy_non_overlapping(&out[0], &pixels[0], len(pixels))
    } else if inPixelFmt == .RGBA || inPixelFmt == .BGRA { //convert pixel format
        for i in 0..<len(pixels)/4 {//TODO SIMD (xfigd)    
            out[i * 4 + 0] = pixels[i * 4 + 2]
            out[i * 4 + 1] = pixels[i * 4 + 1]
            out[i * 4 + 2] = pixels[i * 4 + 0]
            out[i * 4 + 3] = pixels[i * 4 + 3]
        }   
    } else {
        trace.printlnLog("ColorFmtConvertDefault: Unsupported pixel format: ", inPixelFmt)
    }
}

ColorFmtConvertDefaultOverlap :: proc "contextless" (pixels:[]byte, out:[]byte, inPixelFmt:color_fmt = .RGBA) {
    defcol := default_color_fmt()
    if defcol == inPixelFmt {
        mem.copy(&out[0], &pixels[0], len(pixels))
    } else if inPixelFmt == .RGBA || inPixelFmt == .BGRA { //convert pixel format
        for i in 0..<len(pixels)/4 {//TODO SIMD (xfigd)
            temp:[4]byte
            temp[0] = pixels[i * 4 + 2]
            temp[1] = pixels[i * 4 + 1]
            temp[2] = pixels[i * 4 + 0]
            temp[3] = pixels[i * 4 + 3]

            out[i * 4 + 0] = temp[0]
            out[i * 4 + 1] = temp[1]
            out[i * 4 + 2] = temp[2]
            out[i * 4 + 3] = temp[3]
        }   
    } else {
        trace.printlnLog("ColorFmtConvertDefault: Unsupported pixel format: ", inPixelFmt)
    }
}


TileTextureArray_Init :: proc(self:^TileTextureArray, #any_int tile_width:int, #any_int tile_height:int, #any_int width:int, #any_int count:int, pixels:[]byte, sampler:vk.Sampler = 0, 
inPixelFmt:color_fmt = .RGBA) {
    mem.ICheckInit_Init(&self.checkInit)
    self.sampler = sampler == 0 ? vkLinearSampler : sampler
    self.set.bindings = __singlePoolBinding[:]
    self.set.size = __singleSamplerPoolSizes[:]
    self.set.layout = vkTexDescriptorSetLayout2
    self.set.__set = 0
    bit :: 4//outBit count default 4
    allocPixels := mem.make_non_zeroed_slice([]byte, count * tile_width * tile_height * bit, engineDefAllocator)

    //convert tilemap pixel data format to tile image data format arranged sequentially
    cnt:int
    row := math.floor_div(width, tile_width)
    col := math.floor_div(count, row)

    for y in 0..<col {
        for x in 0..<row {
            for h in 0..<tile_height {
                start := cnt * (tile_width * tile_height * bit) + h * tile_width * bit
                startP := (y * tile_height + h) * (width * bit) + x * tile_width * bit
                ColorFmtConvertDefault(pixels[startP:startP + tile_width * bit], allocPixels[start:start + tile_width * bit], inPixelFmt)
            }
            cnt += 1
        }
    }
  
    VkBufferResource_CreateTexture(&self.texture, {
        width = auto_cast tile_width,
        height = auto_cast tile_height,
        useGCPUMem = false,
        format = .DefaultColor,
        samples = 1,
        len = auto_cast count,
        textureUsage = {.IMAGE_RESOURCE},
        type = .TEX2D,
    }, self.sampler, allocPixels, false, engineDefAllocator)

    self.set.__resources = mem.make_non_zeroed_slice([]VkUnionResource, 1, vkTempArenaAllocator)
    self.set.__resources[0] = &self.texture
    VkUpdateDescriptorSets(mem.slice_ptr(&self.set, 1))
}
TileTextureArray_Deinit :: #force_inline proc(self:^TileTextureArray) {
    mem.ICheckInit_Deinit(&self.checkInit)
    VkBufferResource_Deinit(&self.texture)
}
TileTextureArray_Width :: #force_inline proc "contextless" (self:^TileTextureArray) -> int {
    return auto_cast self.texture.option.width
}   
TileTextureArray_Height :: #force_inline proc "contextless" (self:^TileTextureArray) -> int {
    return auto_cast self.texture.option.height
}
TileTextureArray_Count :: #force_inline proc "contextless" (self:^TileTextureArray) -> int {
    return auto_cast self.texture.option.len
}


ImagePixelPerfectPoint :: proc "contextless" (img:^$ANY_IMAGE, p:linalg.PointF, canvasW:f32, canvasH:f32, pivot:ImageCenterPtPos) -> linalg.PointF where IsAnyImageType(ANY_IMAGE) {
    width := __windowWidth
    height := __windowHeight
    widthF := f32(width)
    heightF := f32(height)
    if widthF / heightF > canvasW / canvasH {
        if canvasH != heightF do return p
    } else {
        if canvasW != width do return p
    }
    p = linalg.floor(p)
    if width % 2 == 0 do p.x -= 0.5
    if height % 2 == 0 do p.y += 0.5

    #partial switch pivot {
        case .Center:
            if img.src.texture.option.width % 2 != 0 do p.x += 0.5
            if img.src.texture.option.height % 2 != 0 do p.y -= 0.5
        case .Left, .Right:
            if img.src.texture.option.height % 2 != 0 do p.y -= 0.5
        case .Top, .Bottom:
            if img.src.texture.option.width % 2 != 0 do p.x += 0.5
    }
    return p
}
