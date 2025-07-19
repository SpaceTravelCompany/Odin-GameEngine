package engine

import "core:math"
import "core:mem"
import "core:slice"
import "core:sync"
import "core:thread"
import "core:debug/trace"
import "core:math/linalg"
import "base:intrinsics"
import "base:runtime"
import vk "vendor:vulkan"

@private Graphics_Create :: proc() {
    ColorTransform_InitMatrixRaw(&__defColorTransform)
}

@private Graphics_Clean :: proc() {
    ColorTransform_Deinit(&__defColorTransform)
}

ResourceUsage :: enum {GPU,CPU}

IObjectVTable :: struct {
     __GetUniformResources: #type proc (self:^IObject) -> []VkUnionResource,
    Draw: #type proc (self:^IObject, cmd:vk.CommandBuffer),
    Deinit: #type proc (self:^IObject),
    Update: #type proc (self:^IObject),
    Size: #type proc (self:^IObject),
}

IAnimateObjectVTable :: struct {
    using _: IObjectVTable,
    get_frame_cnt: #type proc "contextless" (self:^ianimate_object) -> u32,
}

IObject :: struct {
    using _: __MatrixIn,
    set:VkDescriptorSet,
    camera: ^Camera,
    projection: ^Projection,
    colorTransform: ^ColorTransform,
    actualType: typeid,
    vtable: ^IObjectVTable,
}


ColorTransform :: struct {
    mat: linalg.Matrix,
    matUniform:VkBufferResource,
    checkInit: mem.ICheckInit,
}

@private __defColorTransform : ColorTransform

__MatrixIn :: struct {
    mat: linalg.Matrix,
    matUniform:VkBufferResource,
    checkInit: mem.ICheckInit,
}


ColorTransform_InitMatrixRaw :: proc(self:^ColorTransform, mat:linalg.Matrix = {1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}) {
    self.mat = mat
    __ColorTransform_Init(self)
}

@private __ColorTransform_Init :: #force_inline proc(self:^ColorTransform) {
    mem.ICheckInit_Init(&self.checkInit)
    VkBufferResource_CreateBuffer(&self.matUniform, {
        len = size_of(linalg.Matrix),
        type = .UNIFORM,
        resourceUsage = .CPU,
    }, mem.ptr_to_bytes(&self.mat), true)
}

ColorTransform_Deinit :: proc(self:^ColorTransform) {
    mem.ICheckInit_Deinit(&self.checkInit)
    VkBufferResource_Deinit(&self.matUniform)
}

ColorTransform_UpdateMatrixRaw :: proc(self:^ColorTransform, _mat:linalg.Matrix) {
    mem.ICheckInit_Check(&self.checkInit)
    self.mat = _mat
    VkBufferResource_CopyUpdate(&self.matUniform, &self.mat)
}


@(require_results)
__SRTC_2D_Matrix :: proc "contextless" (t: linalg.Point3DF, s: linalg.PointF, r: f32, cp:linalg.PointF) -> linalg.Matrix4x4f32 {
	pivot := linalg.matrix4_translate(linalg.Point3DF{cp.x,cp.y,0.0})
	translation := linalg.matrix4_translate(t)
	rotation := linalg.matrix4_rotate_f32(r, linalg.Vector3f32{0.0, 0.0, 1.0})
	scale := linalg.matrix4_scale(linalg.Point3DF{s.x,s.y,1.0})
	return linalg.mul(translation, linalg.mul(rotation, linalg.mul(pivot, scale)))
}

@(require_results)
__SRT_2D_Matrix :: proc "contextless" (t: linalg.Point3DF, s: linalg.PointF, r: f32) -> linalg.Matrix4x4f32 {
	translation := linalg.matrix4_translate(t)
	rotation := linalg.matrix4_rotate_f32(r, linalg.Vector3f32{0.0, 0.0, 1.0})
	scale := linalg.matrix4_scale(linalg.Point3DF{s.x,s.y,1.0})
	return linalg.mul(translation, linalg.mul(rotation, scale))
}

@(require_results)
__ST_2D_Matrix :: proc "contextless" (t: linalg.Point3DF, s: linalg.PointF) -> linalg.Matrix4x4f32 {
	translation := linalg.matrix4_translate(t)
	scale := linalg.matrix4_scale(linalg.Point3DF{s.x,s.y,1.0})
	return linalg.mul(translation, scale)
}

@(require_results)
__RT_2D_Matrix :: proc "contextless" (t: linalg.Point3DF, r: f32) -> linalg.Matrix4x4f32 {
	translation := linalg.matrix4_translate(t)
    rotation := linalg.matrix4_rotate_f32(r, linalg.Vector3f32{0.0, 0.0, 1.0})
	return linalg.mul(translation, rotation)
}


@(require_results)
__T_2D_Matrix :: proc "contextless" (t: linalg.Point3DF) -> linalg.Matrix4x4f32 {
	translation := linalg.matrix4_translate(t)
	return translation
}


SRT_2D_Matrix :: proc {
    __SRTC_2D_Matrix,
    __ST_2D_Matrix,
    __RT_2D_Matrix,
    __T_2D_Matrix,
    __SRT_2D_Matrix,
}

@(require_results)
__SRC_2D_Matrix :: proc "contextless" (s: linalg.PointF, r: f32, cp:linalg.PointF) -> linalg.Matrix4x4f32 {
	pivot := linalg.matrix4_translate(linalg.Point3DF{cp.x,cp.y,0.0})
	rotation := linalg.matrix4_rotate_f32(r, linalg.Vector3f32{0.0, 0.0, 1.0})
	scale := linalg.matrix4_scale(linalg.Point3DF{s.x,s.y,1.0})
	return linalg.mul(rotation, linalg.mul(pivot, scale))
}

@(require_results)
__SR_2D_Matrix :: proc "contextless" (s: linalg.PointF, r: f32) -> linalg.Matrix4x4f32 {
	rotation := linalg.matrix4_rotate_f32(r, linalg.Vector3f32{0.0, 0.0, 1.0})
	scale := linalg.matrix4_scale(linalg.Point3DF{s.x,s.y,1.0})
	return linalg.mul(rotation, scale)
}

@(require_results)
__S_2D_Matrix :: proc "contextless" (s: linalg.PointF) -> linalg.Matrix4x4f32 {
	scale := linalg.matrix4_scale(linalg.Point3DF{s.x,s.y,1.0})
	return scale
}

@(require_results)
__R_2D_Matrix :: proc "contextless" (r: f32) -> linalg.Matrix4x4f32 {
    rotation := linalg.matrix4_rotate_f32(r, linalg.Vector3f32{0.0, 0.0, 1.0})
	return rotation
}

SR_2D_Matrix :: proc {
    __SRC_2D_Matrix,
    __S_2D_Matrix,
    __R_2D_Matrix,
    __SR_2D_Matrix,
}

@(require_results)
SRT_2D_Matrix2 :: proc "contextless" (t: linalg.Point3DF, s: linalg.PointF, r: f32, cp:linalg.PointF) -> linalg.Matrix4x4f32 {
    if cp != {0.0, 0.0} {
        return __SRTC_2D_Matrix(t,s,r,cp)
    }
    if r != 0.0 {
        if s != {1.0, 1.0} {
            return __SRT_2D_Matrix(t,s,r)
        } else {
            return __RT_2D_Matrix(t,r)
        }
    }
    if s != {1.0, 1.0} {
        return __ST_2D_Matrix(t,s)
    }
    return __T_2D_Matrix(t)
}

@(require_results)
SR_2D_Matrix2 :: proc "contextless" (s: linalg.PointF, r: f32, cp:linalg.PointF) -> Maybe(linalg.Matrix4x4f32) {
    if cp != {0.0, 0.0} {
        return __SRC_2D_Matrix(s,r,cp)
    }
    if r != 0.0 {
        if s != {1.0, 1.0} {
            return __SR_2D_Matrix(s,r)
        } else {
            return __R_2D_Matrix(r)
        }
    }
    if s != {1.0, 1.0} {
        return __S_2D_Matrix(s)
    }
    return nil
}

IObject_Init :: proc(self:^IObject, $actualType:typeid,
    pos:linalg.Point3DF, rotation:f32, scale:linalg.PointF = {1,1},
    camera:^Camera, projection:^Projection, colorTransform:^ColorTransform = nil, pivot:linalg.PointF = {0.0, 0.0})
    where actualType != IObject && intrinsics.type_is_subtype_of(actualType, IObject) {

    mem.ICheckInit_Init(&self.checkInit)
    self.camera = camera
    self.projection = projection
    self.colorTransform = colorTransform == nil ? &__defColorTransform : colorTransform
    
    self.mat = SRT_2D_Matrix2(pos, scale, rotation, pivot)

    VkBufferResource_CreateBuffer(&self.matUniform, {
        len = size_of(linalg.Matrix),
        type = .UNIFORM,
        resourceUsage = .CPU,
    }, mem.ptr_to_bytes(&self.mat), true)

    resources := __GetUniformResources(self)
    defer delete(resources, context.temp_allocator)
    __IObject_UpdateUniform(self, resources)

    self.actualType = actualType
}

_Super_IObject_Deinit :: #force_inline proc (self:^IObject) {
    mem.ICheckInit_Deinit(&self.checkInit)
    VkBufferResource_Deinit(&self.matUniform)
}

IObject_Init2 :: proc(self:^IObject, $actualType:typeid,
    camera:^Camera, projection:^Projection, colorTransform:^ColorTransform = nil)
    where actualType != IObject && intrinsics.type_is_subtype_of(actualType, IObject) {

    mem.ICheckInit_Init(&self.checkInit)
    self.camera = camera
    self.projection = projection
    self.colorTransform = colorTransform == nil ? &__defColorTransform : colorTransform

    self.actualType = actualType
}

//!alloc result array in temp_allocator
@private __GetUniformResources :: proc(self:^IObject) -> []VkUnionResource {
    if self.vtable != nil && self.vtable.__GetUniformResources != nil {
        return self.vtable.__GetUniformResources(self)
    } else {
        trace.panic_log("__GetUniformResources is not implemented")
    }
}

@private __GetUniformResources_AnimateImage :: #force_inline proc(self:^IObject) -> []VkUnionResource {
    res := mem.make_non_zeroed([]VkUnionResource, 5, context.temp_allocator)
    res[0] = &self.matUniform
    res[1] = &self.camera.matUniform
    res[2] = &self.projection.matUniform
    res[3] = &self.colorTransform.matUniform

    animateImage : ^AnimateImage= auto_cast self
    res[4] = &animateImage.frameUniform
    return res[:]
}

@private __GetUniformResources_TileImage :: #force_inline proc(self:^IObject) -> []VkUnionResource {
    res := mem.make_non_zeroed([]VkUnionResource, 5, context.temp_allocator)
    res[0] = &self.matUniform
    res[1] = &self.camera.matUniform
    res[2] = &self.projection.matUniform
    res[3] = &self.colorTransform.matUniform

    tileImage : ^TileImage = auto_cast self
    res[4] = &tileImage.tileUniform
    return res[:]
}

@private __GetUniformResources_Default :: #force_inline proc(self:^IObject) -> []VkUnionResource {
    res := mem.make_non_zeroed([]VkUnionResource, 4, context.temp_allocator)
    res[0] = &self.matUniform
    res[1] = &self.camera.matUniform
    res[2] = &self.projection.matUniform
    res[3] = &self.colorTransform.matUniform

    return res[:]
}

@private __IObject_UpdateUniform :: #force_inline proc(self:^IObject, resources:[]VkUnionResource) {
    mem.ICheckInit_Check(&self.checkInit)
    mem.copy_non_overlapping(&self.set.__resources[0], &resources[0], len(resources) * size_of(VkUnionResource))
    VkUpdateDescriptorSets(mem.slice_ptr(&self.set, 1))
}

IObject_UpdateTransform :: proc(self:^IObject, pos:linalg.Point3DF, rotation:f32 = 0.0, scale:linalg.PointF = {1.0,1.0}, pivot:linalg.PointF = {0.0,0.0}) {
    mem.ICheckInit_Check(&self.checkInit)
    self.mat = SRT_2D_Matrix2(pos, scale, rotation, pivot)

    if self.matUniform.__resource == 0 {
        VkBufferResource_CreateBuffer(&self.matUniform, {
            len = size_of(linalg.Matrix),
            type = .UNIFORM,
            resourceUsage = .CPU,
        }, mem.ptr_to_bytes(&self.mat), true)

        resources := __GetUniformResources(self)
        defer delete(resources, context.temp_allocator)
        __IObject_UpdateUniform(self, resources)
    } else {
        VkBufferResource_CopyUpdate(&self.matUniform, &self.mat)
    }
}
IObject_UpdateTransformMatrixRaw :: proc(self:^IObject, _mat:linalg.Matrix) {
    mem.ICheckInit_Check(&self.checkInit)
    self.mat = _mat
    
    if self.matUniform.__resource == 0 {
        VkBufferResource_CreateBuffer(&self.matUniform, {
            len = size_of(linalg.Matrix),
            type = .UNIFORM,
            resourceUsage = .CPU,
        }, mem.ptr_to_bytes(&self.mat), true)

        resources := __GetUniformResources(self)
        defer delete(resources, context.temp_allocator)
        __IObject_UpdateUniform(self, resources)
    } else {
        VkBufferResource_CopyUpdate(&self.matUniform, &self.mat)
    }
}

IObject_UpdateTransformMatrix :: proc(self:^IObject) {
    mem.ICheckInit_Check(&self.checkInit)
    
    if self.matUniform.__resource == 0 {
        VkBufferResource_CreateBuffer(&self.matUniform, {
            len = size_of(linalg.Matrix),
            type = .UNIFORM,
            resourceUsage = .CPU,
        }, mem.ptr_to_bytes(&self.mat), true)

        resources := __GetUniformResources(self)
        defer delete(resources, context.temp_allocator)
        __IObject_UpdateUniform(self, resources)
    } else {
        VkBufferResource_CopyUpdate(&self.matUniform, &self.mat)
    }
}

IObject_ChangeColorTransform :: proc(self:^IObject, colorTransform:^ColorTransform) {
    mem.ICheckInit_Check(&self.checkInit)
    self.colorTransform = colorTransform
    __IObject_UpdateUniform(self, __GetUniformResources(self))
}
IObject_UpdateCamera :: proc(self:^IObject, camera:^Camera) {
    mem.ICheckInit_Check(&self.checkInit)
    self.camera = camera
    __IObject_UpdateUniform(self, __GetUniformResources(self))
}
IObject_UpdateProjection :: proc(self:^IObject, projection:^Projection) {
    mem.ICheckInit_Check(&self.checkInit)
    self.projection = projection
    __IObject_UpdateUniform(self, __GetUniformResources(self))
}
IObject_GetColorTransform :: #force_inline proc "contextless" (self:^IObject) -> ^ColorTransform {
    mem.ICheckInit_Check(&self.checkInit)
    return self.colorTransform
}
IObject_GetCamera :: #force_inline proc "contextless" (self:^IObject) -> ^Camera {
    mem.ICheckInit_Check(&self.checkInit)
    return self.camera
}
IObject_GetProjection :: #force_inline proc "contextless" (self:^IObject) -> ^Projection {
    mem.ICheckInit_Check(&self.checkInit)
    return self.projection
}

IObject_GetActualType :: #force_inline proc "contextless" (self:^IObject) -> typeid {
    return self.actualType
}

IObject_Draw :: proc (self:^IObject, cmd:vk.CommandBuffer) {
    if self.vtable != nil && self.vtable.Draw != nil {
        self.vtable.Draw(self, cmd)
    } else {
        trace.panic_log("IObjectType_Draw: unknown object type")
    }
}

IObject_Deinit :: proc(self:^IObject) {
    if self.vtable != nil && self.vtable.Deinit != nil {
        self.vtable.Deinit(self)
    } else {
        trace.panic_log("IObjectType_Deinit: unknown object type")
    }
}

IObject_Update :: proc(self:^IObject) {
    if self.vtable != nil && self.vtable.Update != nil {
        self.vtable.Update(self)
    }
    //Update Not Required Default
}

IObject_Size :: proc(self:^IObject) {
    if self.vtable != nil && self.vtable.Size != nil {
        self.vtable.Size(self)
    }
    //Size Not Required Default
}



SetRenderClearColor :: proc "contextless" (color:linalg.Point3DwF) {
    gClearColor = color
}

//AUTO DELETE USE engineDefAllocator
@private __VertexBuf_Init :: proc (self:^__VertexBuf($NodeType), array:[]NodeType, _flag:ResourceUsage, _useGPUMem := false) {
    mem.ICheckInit_Init(&self.checkInit)
    if len(array) == 0 do trace.panic_log("VertexBuf_Init: array is empty")
    VkBufferResource_CreateBuffer(&self.buf, {
        len = vk.DeviceSize(len(array) * size_of(NodeType)),
        type = .VERTEX,
        resourceUsage = _flag,
        single = false,
        useGCPUMem = _useGPUMem,
    }, mem.slice_to_bytes(array), false, engineDefAllocator)
}

@private __VertexBuf_Deinit :: proc (self:^__VertexBuf($NodeType)) {
    mem.ICheckInit_Deinit(&self.checkInit)

    VkBufferResource_Deinit(&self.buf)
}

@private __VertexBuf_Update :: proc (self:^__VertexBuf($NodeType), array:[]NodeType) {
    VkBufferResource_MapUpdateSlice(&self.buf, array, engineDefAllocator)
}

//AUTO DELETE USE engineDefAllocator
@private __StorageBuf_Init :: proc (self:^__StorageBuf($NodeType), array:[]NodeType, _flag:ResourceUsage, _useGPUMem := false) {
    mem.ICheckInit_Init(&self.checkInit)
    if len(array) == 0 do trace.panic_log("StorageBuf_Init: array is empty")
    VkBufferResource_CreateBuffer(&self.buf, {
        len = vk.DeviceSize(len(array) * size_of(NodeType)),
        type = .STORAGE,
        resourceUsage = _flag,
        single = false,
        useGCPUMem = _useGPUMem,
    }, mem.slice_to_bytes(array), false, engineDefAllocator)
}

@private __StorageBuf_Deinit :: proc (self:^__StorageBuf($NodeType)) {
    mem.ICheckInit_Deinit(&self.checkInit)

    VkBufferResource_Deinit(&self.buf)
}

@private __StorageBuf_Update :: proc (self:^__StorageBuf($NodeType), array:[]NodeType) {
    VkBufferResource_MapUpdateSlice(&self.buf, array, engineDefAllocator)
}

//AUTO DELETE USE engineDefAllocator
@private __IndexBuf_Init :: proc (self:^__IndexBuf, array:[]u32, _flag:ResourceUsage, _useGPUMem := false) {
    mem.ICheckInit_Init(&self.checkInit)
    if len(array) == 0 do trace.panic_log("IndexBuf_Init: array is empty")
    VkBufferResource_CreateBuffer(&self.buf, {
        len = vk.DeviceSize(len(array) * size_of(u32)),
        type = .INDEX,
        resourceUsage = _flag,
        useGCPUMem = _useGPUMem,
    }, mem.slice_to_bytes(array), false, engineDefAllocator)
}


@private __IndexBuf_Deinit :: proc (self:^__IndexBuf) {
    mem.ICheckInit_Deinit(&self.checkInit)

    VkBufferResource_Deinit(&self.buf)
}

@private __IndexBuf_Update :: #force_inline proc (self:^__IndexBuf, array:[]u32) {
    VkBufferResource_MapUpdateSlice(&self.buf, array, engineDefAllocator)
}

@private __VertexBuf :: struct($NodeType:typeid) {
    buf:VkBufferResource,
    checkInit: mem.ICheckInit,
}

@private __IndexBuf :: distinct __VertexBuf(u32)
@private __StorageBuf :: struct($NodeType:typeid) {
    buf:VkBufferResource,
    checkInit: ICheckInit,
}


//!do not use anymore
// AllocObjectNonZeroed :: #force_inline proc($T:typeid) -> (^T, runtime.Allocator_Error) where intrinsics.type_is_subtype_of(T, IObject) #optional_allocator_error {
//     obj, err := mem.alloc_bytes_non_zeroed(size_of(T),align_of(T), engineDefAllocator)
//     if err != .None do return nil, err
// 	return transmute(^T)raw_data(obj), .None
// }

// AllocObjectSliceNonZeroed :: #force_inline proc($T:typeid, #any_int count:int) -> ([]T, runtime.Allocator_Error) where intrinsics.type_is_subtype_of(T, IObject) #optional_allocator_error {
//     arr, err := mem.alloc_bytes_non_zeroed(count * size_of(T), align_of(T), engineDefAllocator)
//     if err != .None do return nil, err
//     s := runtime.Raw_Slice{raw_data(arr), count}
//     return transmute([]T)s, .None
// }

// AllocObjectDynamicNonZeroed :: #force_inline proc($T:typeid) -> ([dynamic]T, runtime.Allocator_Error) where intrinsics.type_is_subtype_of(T, IObject) #optional_allocator_error {
//     res, err := make_non_zeroed_dynamic_array([dynamic]T, engineDefAllocator)
//     if err != .None do return nil, err
//     return res, .None
// }

AllocObject :: #force_inline proc($T:typeid) -> (^T, runtime.Allocator_Error) where intrinsics.type_is_subtype_of(T, IObject) #optional_allocator_error {
    obj, err := mem.alloc_bytes(size_of(T),align_of(T), engineDefAllocator)
    if err != .None do return nil, err
	return transmute(^T)raw_data(obj), .None
}

AllocObjectSlice :: #force_inline proc($T:typeid, #any_int count:int) -> ([]T, runtime.Allocator_Error) where intrinsics.type_is_subtype_of(T, IObject) #optional_allocator_error {
    arr, err := mem.alloc_bytes(count * size_of(T), align_of(T), engineDefAllocator)
    if err != .None do return nil, err
    s := runtime.Raw_Slice{raw_data(arr), count}
    return transmute([]T)s, .None
}

AllocObjectDynamic :: #force_inline proc($T:typeid) -> ([dynamic]T, runtime.Allocator_Error) where intrinsics.type_is_subtype_of(T, IObject) #optional_allocator_error {
    res, err := make([dynamic]T, engineDefAllocator)
    if err != .None do return nil, err
    return res, .None
}

FreeObject :: #force_inline proc(obj:^$T) where intrinsics.type_is_subtype_of(T, IObject) {
    aObj := FREE_OBJ{
        typeSize = size_of(T),
        len = 1,
        deinit = obj.vtable.Deinit,
        obj = rawptr(obj),
    }
    sync.mutex_lock(&gFreeObjectMtx)
    append(&gFreeObjects, aObj)
    sync.mutex_unlock(&gFreeObjectMtx)
}

FreeObjectSlice :: #force_inline proc(arr:$T/[]$E) where intrinsics.type_is_subtype_of(E, IObject) {
    aObj := FREE_OBJ{
        typeSize = size_of(E),
        len = len(arr),
        deinit = len(arr) > 0 ? arr[0].vtable.Deinit : nil,
        obj = rawptr(raw_data(arr)),
    }
    sync.mutex_lock(&gFreeObjectMtx)
    append(&gFreeObjects, aObj)
    sync.mutex_unlock(&gFreeObjectMtx)
}

FreeObjectDynamic :: #force_inline proc(arr:$T/[dynamic]$E) where intrinsics.type_is_subtype_of(E, IObject) {
    aObj := FREE_OBJ{
        typeSize = size_of(E),
        len = cap(arr),
        deinit = len(arr) > 0 ? arr[0].vtable.Deinit : nil,
        obj = rawptr(raw_data(arr)),
    }
    sync.mutex_lock(&gFreeObjectMtx)
    append(&gFreeObjects, aObj)
    sync.mutex_unlock(&gFreeObjectMtx)
}

GraphicsWaitAllOps :: #force_inline proc () {
    if IsInMainThread() {
        vkOpExecute(true)
    } else {
        vkWaitAllOp()
    }
}