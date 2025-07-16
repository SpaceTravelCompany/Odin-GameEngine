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

@private __ShapeSrcIn :: struct {
    //?vertexBuf, indexBuf에 checkInit: ICheckInit 있으므로 따로 필요없음
    vertexBuf:__VertexBuf(geometry.ShapeVertex2D),
    indexBuf:__IndexBuf,
}       

ShapeSrc :: struct {
    using _:__ShapeSrcIn,
    rect:linalg.RectF,
}

Shape :: struct {
    using object:IObject,
    using _:__ShapeIn,
}

@private __ShapeIn :: struct {
    src: ^ShapeSrc,
}

@private ShapeVTable :IObjectVTable = IObjectVTable{
    Draw = auto_cast _Super_Shape_Draw,
    Deinit = auto_cast _Super_Shape_Deinit,
}


Shape_Init :: proc(self:^Shape, $actualType:typeid, src:^ShapeSrc, pos:linalg.Point3DF,
camera:^Camera, projection:^Projection,  rotation:f32 = 0.0, scale:linalg.PointF = {1,1}, colorTransform:^ColorTransform = nil, pivot:linalg.PointF = {0.0, 0.0}, vtable:^IObjectVTable = nil)
 where intrinsics.type_is_subtype_of(actualType, Shape) {
    self.src = src

    self.set.bindings = __transformUniformPoolBinding[:]
    self.set.size = __transformUniformPoolSizes[:]
    self.set.layout = vkShapeDescriptorSetLayout

    self.vtable = vtable == nil ? &ShapeVTable : vtable
    if self.vtable.Draw == nil do self.vtable.Draw = auto_cast _Super_Shape_Draw
    if self.vtable.Deinit == nil do self.vtable.Deinit = auto_cast _Super_Shape_Deinit

    self.vtable.__GetUniformResources = auto_cast __GetUniformResources_Default

    IObject_Init(self, actualType, pos, rotation, scale, camera, projection, colorTransform, pivot)
}

Shape_Init2 :: proc(self:^Shape, $actualType:typeid, src:^ShapeSrc,
camera:^Camera, projection:^Projection, colorTransform:^ColorTransform = nil, vtable:^IObjectVTable = nil)
 where intrinsics.type_is_subtype_of(actualType, Shape) {
    self.src = src

    self.set.bindings = __transformUniformPoolBinding[:]
    self.set.size = __transformUniformPoolSizes[:]
    self.set.layout = vkShapeDescriptorSetLayout

    self.vtable = vtable == nil ? &ShapeVTable : vtable
    if self.vtable.Draw == nil do self.vtable.Draw = auto_cast _Super_Shape_Draw
    if self.vtable.Deinit == nil do self.vtable.Deinit = auto_cast _Super_Shape_Deinit

    self.vtable.__GetUniformResources = auto_cast __GetUniformResources_Default

    IObject_Init2(self, actualType, camera, projection, colorTransform)
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

    vk.CmdBindPipeline(cmd, .GRAPHICS, vkShapePipeline)
    vk.CmdBindDescriptorSets(cmd, .GRAPHICS, vkShapePipelineLayout, 0, 1, 
        &([]vk.DescriptorSet{self.set.__set})[0], 0, nil)


    offsets: vk.DeviceSize = 0
    vk.CmdBindVertexBuffers(cmd, 0, 1, &self.src.vertexBuf.buf.__resource, &offsets)
    vk.CmdBindIndexBuffer(cmd, self.src.indexBuf.buf.__resource, 0, .UINT32)

    vk.CmdDrawIndexed(cmd, auto_cast (self.src.indexBuf.buf.option.len / size_of(u32)), 1, 0, 0, 0)
}

ShapeSrc_InitRaw :: proc(self:^ShapeSrc, raw:^geometry.RawShape, flag:ResourceUsage = .GPU, colorFlag:ResourceUsage = .CPU) {
    rawC := geometry.RawShape_Clone(raw, engineDefAllocator)
    __VertexBuf_Init(&self.vertexBuf, rawC.vertices, flag)
    __IndexBuf_Init(&self.indexBuf, rawC.indices, flag)
    self.rect = rawC.rect
}

@require_results ShapeSrc_Init :: proc(self:^ShapeSrc, shapes:^geometry.Shapes, flag:ResourceUsage = .GPU, colorFlag:ResourceUsage = .CPU) -> (err:geometry.ShapesError = .None) {
    raw : ^geometry.RawShape
    raw, err = geometry.Shapes_ComputePolygon(shapes, engineDefAllocator)
    if err != .None do return

    __VertexBuf_Init(&self.vertexBuf, raw.vertices, flag)
    __IndexBuf_Init(&self.indexBuf, raw.indices, flag)

    self.rect = raw.rect

    defer free(raw)
    return
}

ShapeSrc_UpdateRaw :: proc(self:^ShapeSrc, raw:^geometry.RawShape) {
    rawC := geometry.RawShape_Clone(raw, engineDefAllocator)
    __VertexBuf_Update(&self.vertexBuf, rawC.vertices)
    __IndexBuf_Update(&self.indexBuf, rawC.indices)

    defer free(rawC)
}

@require_results ShapeSrc_Update :: proc(self:^ShapeSrc, shapes:^geometry.Shapes) -> (err:geometry.ShapesError = .None) {
    raw : ^geometry.RawShape
    raw, err = geometry.Shapes_ComputePolygon(shapes, engineDefAllocator)
    if err != .None do return

    __VertexBuf_Update(&self.vertexBuf, raw.vertices)
    __IndexBuf_Update(&self.indexBuf, raw.indices)
    return
}

ShapeSrc_Deinit :: proc(self:^ShapeSrc) {
    __VertexBuf_Deinit(&self.vertexBuf)
    __IndexBuf_Deinit(&self.indexBuf)
}


ShapeSrc_IsInited :: proc "contextless" (self:^ShapeSrc) -> bool {
    return mem.ICheckInit_IsInited(&self.vertexBuf.checkInit)
}


