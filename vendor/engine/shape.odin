package engine

import "core:math"
import "vendor:engine/geometry"
import "core:mem"
import "core:slice"
import "core:sync"
import "core:math/linalg"
import "base:intrinsics"
import "base:runtime"
import vk "vendor:vulkan"   

ShapeSrc :: struct {
    //?vertexBuf, indexBuf에 checkInit: ICheckInit 있으므로 따로 필요없음
    vertexBufs:[]__VertexBuf(geometry.ShapeVertex2D),
    indexBufs:[]__IndexBuf,
    colBufs:[]VkBufferResource,
    sets:[]VkDescriptorSet,
    rect:linalg.RectF,
}

Shape :: struct {
    using object:IObject,
    src: ^ShapeSrc,
}

@private ShapeVTable :IObjectVTable = IObjectVTable{
    Draw = auto_cast _Super_Shape_Draw,
    Deinit = auto_cast _Super_Shape_Deinit,
}


Shape_Init :: proc(self:^Shape, $actualType:typeid, src:^ShapeSrc, pos:linalg.Point3DF,
camera:^Camera, projection:^Projection,  rotation:f32 = 0.0, scale:linalg.PointF = {1,1}, pivot:linalg.PointF = {0.0, 0.0}, vtable:^IObjectVTable = nil)
 where intrinsics.type_is_subtype_of(actualType, Shape) {
    self.src = src

    self.set.bindings = __shapeUniformPoolBinding[:]
    self.set.size = __shapeUniformPoolSizes[:]
    self.set.layout = vkShapeDescriptorSetLayout

    self.vtable = vtable == nil ? &ShapeVTable : vtable
    if self.vtable.Draw == nil do self.vtable.Draw = auto_cast _Super_Shape_Draw
    if self.vtable.Deinit == nil do self.vtable.Deinit = auto_cast _Super_Shape_Deinit

    if self.vtable.GetUniformResources == nil do self.vtable.GetUniformResources = auto_cast GetUniformResources_Shape

    IObject_Init(self, actualType, pos, rotation, scale, camera, projection, nil, pivot)
}

Shape_Init2 :: proc(self:^Shape, $actualType:typeid, src:^ShapeSrc,
camera:^Camera, projection:^Projection, vtable:^IObjectVTable = nil)
 where intrinsics.type_is_subtype_of(actualType, Shape) {
    self.src = src

    self.set.bindings = __shapeUniformPoolBinding[:]
    self.set.size = __shapeUniformPoolSizes[:]
    self.set.layout = vkShapeDescriptorSetLayout

    self.vtable = vtable == nil ? &ShapeVTable : vtable
    if self.vtable.Draw == nil do self.vtable.Draw = auto_cast _Super_Shape_Draw
    if self.vtable.Deinit == nil do self.vtable.Deinit = auto_cast _Super_Shape_Deinit

    if self.vtable.GetUniformResources == nil do self.vtable.GetUniformResources = auto_cast GetUniformResources_Shape

    IObject_Init2(self, actualType, camera, projection, nil)
}

_Super_Shape_Deinit :: proc(self:^Shape) {
    _Super_IObject_Deinit(auto_cast self)
}

Shape_UpdateSrc :: #force_inline proc "contextless" (self:^Shape, src:^ShapeSrc) {
    mem.ICheckInit_Check(&self.checkInit)
    self.src = src
}
Shape_GetSrc :: #force_inline proc "contextless" (self:^Shape) -> ^ShapeSrc {
    mem.ICheckInit_Check(&self.checkInit)
    return self.src
}
Shape_GetCamera :: #force_inline proc "contextless" (self:^Shape) -> ^Camera {
    return IObject_GetCamera(self)
}
Shape_GetProjection :: #force_inline proc "contextless" (self:^Shape) -> ^Projection {
    return IObject_GetProjection(self)
}
Shape_GetColorTransform :: #force_inline proc "contextless" (self:^Shape) -> ^ColorTransform {
    return IObject_GetColorTransform(self)
}
Shape_UpdateTransform :: #force_inline proc(self:^Shape, pos:linalg.Point3DF, rotation:f32, scale:linalg.PointF = {1,1}, pivot:linalg.PointF = {0.0,0.0}) {
    IObject_UpdateTransform(self, pos, rotation, scale, pivot)
}
Shape_UpdateTransformMatrixRaw :: #force_inline proc(self:^Shape, _mat:linalg.Matrix) {
    IObject_UpdateTransformMatrixRaw(self, _mat)
}
Shape_ChangeColorTransform :: #force_inline proc(self:^Shape, colorTransform:^ColorTransform) {
    IObject_ChangeColorTransform(self, colorTransform)
}
Shape_UpdateCamera :: #force_inline proc(self:^Shape, camera:^Camera) {
    IObject_UpdateCamera(self, camera)
}
Shape_UpdateProjection :: #force_inline proc(self:^Shape, projection:^Projection) {
    IObject_UpdateProjection(self, projection)
}

_Super_Shape_Draw :: proc (self:^Shape, cmd:vk.CommandBuffer) {
    mem.ICheckInit_Check(&self.checkInit)

    for i in 0..<len(self.src.vertexBufs) {
        vk.CmdBindPipeline(cmd, .GRAPHICS, vkShapePipeline)
        vk.CmdBindDescriptorSets(cmd, .GRAPHICS, vkShapePipelineLayout, 0, 1, &self.set.__set, 0, nil)

        offsets : vk.DeviceSize = 0
        vk.CmdBindVertexBuffers(cmd, 0, 1, &self.src.vertexBufs[i].buf.__resource, &offsets)
        vk.CmdBindIndexBuffer(cmd, self.src.indexBufs[i].buf.__resource, offsets, vk.IndexType.UINT32)

        vk.CmdDrawIndexed(cmd, u32(self.src.indexBufs[i].buf.option.len / vk.DeviceSize(size_of(u32))), 1, 0, 0, 0)


        vk.CmdBindPipeline(cmd, .GRAPHICS, vkShapeQuadPipeline)
        vk.CmdBindDescriptorSets(cmd, .GRAPHICS, vkShapeQuadPipelineLayout, 0, 1, &self.src.sets[i].__set, 0, nil)

        vk.CmdDraw(cmd, 6, 1, 0, 0)
    }
}

ShapeSrc_InitRaw :: proc(self:^ShapeSrc, raw:^geometry.RawShape, flag:ResourceUsage = .GPU, colorFlag:ResourceUsage = .CPU) {
    rawC := geometry.RawShape_Clone(raw, engineDefAllocator)
    __ShapeSrc_Init(self, rawC, flag, colorFlag)
    defer free(rawC)
}

@private __ShapeSrc_Init :: proc(self:^ShapeSrc, raw:^geometry.RawShape, flag:ResourceUsage = .GPU, colorFlag:ResourceUsage = .CPU) {
    self.vertexBufs = mem.make_non_zeroed_slice([]__VertexBuf(geometry.ShapeVertex2D), len(raw.vertices), engineDefAllocator)
    self.indexBufs = mem.make_non_zeroed_slice([]__IndexBuf, len(raw.indices), engineDefAllocator)
    self.colBufs = mem.make_non_zeroed_slice([]VkBufferResource, len(raw.colors), engineDefAllocator)
    self.sets = mem.make_non_zeroed_slice([]VkDescriptorSet, len(raw.colors), engineDefAllocator)

    for i in 0..<len(raw.vertices) {
        __VertexBuf_Init(&self.vertexBufs[i], raw.vertices[i], flag)
        __IndexBuf_Init(&self.indexBufs[i], raw.indices[i], flag)

        self.sets[i].bindings = __singlePoolBinding[:]
        self.sets[i].size = __singleUniformPoolSizes[:]
        self.sets[i].layout = vkShapeQuadDescriptorSetLayout
        self.sets[i].__resources = mem.make_non_zeroed_slice([]VkUnionResource, 1, vkTempArenaAllocator)
        self.sets[i].__resources[0] = &self.colBufs[i]

        VkBufferResource_CreateBuffer(&self.colBufs[i], {
            len = size_of(linalg.Point3DwF),
            type = .UNIFORM,
            resourceUsage = colorFlag,
        }, mem.ptr_to_bytes(&raw.colors[i]), true)
    }
    VkUpdateDescriptorSets(self.sets)
    self.rect = raw.rect
}

@require_results ShapeSrc_Init :: proc(self:^ShapeSrc, shapes:^geometry.Shapes, flag:ResourceUsage = .GPU, colorFlag:ResourceUsage = .CPU) -> (err:geometry.ShapesError = .None) {
    raw : ^geometry.RawShape
    raw, err = geometry.Shapes_ComputePolygon(shapes, engineDefAllocator)
    if err != .None do return

    __ShapeSrc_Init(self, raw, flag, colorFlag)

    defer free(raw)
    return
}

ShapeSrc_ColorUpdate :: proc(self:^ShapeSrc, #any_int start_idx:int, colors:[]linalg.Point3DwF) {
    for i in start_idx..<start_idx + len(colors) {
        VkBufferResource_CopyUpdate(&self.colBufs[i], &colors[i], engineDefAllocator)
    }
}

ShapeSrc_Deinit :: proc(self:^ShapeSrc) {
    for i in 0..<len(self.vertexBufs) {
        __VertexBuf_Deinit(&self.vertexBufs[i])
        __IndexBuf_Deinit(&self.indexBufs[i])
        VkBufferResource_Deinit(&self.colBufs[i])
    }
    delete(self.vertexBufs, engineDefAllocator)
    delete(self.indexBufs, engineDefAllocator)
    delete(self.colBufs, engineDefAllocator)
    delete(self.sets, engineDefAllocator)
}


ShapeSrc_IsInited :: proc "contextless" (self:^ShapeSrc) -> bool {
    if len(self.vertexBufs) == 0 do return false
    return mem.ICheckInit_IsInited(&self.vertexBufs[0].checkInit)
}


