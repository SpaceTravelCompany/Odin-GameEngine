package engine

import "core:math"
import "core:mem"
import "core:slice"
import "core:sync"
import "core:math/linalg"
import "base:intrinsics"
import "base:runtime"
import vk "vendor:vulkan"
import graphics_api "./graphics_api"

Camera :: struct {
    using _: __MatrixIn,
}

Camera_InitMatrixRaw :: proc (self:^Camera, mat:linalg.Matrix) {
    mem.ICheckInit_Init(&self.checkInit)
    self.mat = mat
    __Camera_Init(self)
}

@private __Camera_Init :: #force_inline proc(self:^Camera) {
    mem.ICheckInit_Init(&self.checkInit)
    graphics_api.BufferResource_CreateBuffer(&self.matUniform, {
        len = size_of(linalg.Matrix),
        type = .UNIFORM,
        resourceUsage = .CPU,
    }, mem.ptr_to_bytes(&self.mat), true)
}

Camera_Deinit :: proc(self:^Camera) {
    mem.ICheckInit_Deinit(&self.checkInit)
    BufferResource_Deinit(&self.matUniform)
}

Camera_UpdateMatrixRaw :: proc(self:^Camera, _mat:linalg.Matrix) {
    mem.ICheckInit_Check(&self.checkInit)
    self.mat = _mat
    graphics_api.BufferResource_CopyUpdate(&self.matUniform, &self.mat)
}

@private __Camera_Update :: #force_inline proc(self:^Camera, eyeVec:linalg.Point3DF, focusVec:linalg.Point3DF, upVec:linalg.Point3DF = {0,0,1}) {
    f := linalg.normalize(focusVec - eyeVec)
	s := linalg.normalize(linalg.cross(upVec, f))
	u := linalg.normalize(linalg.cross(f, s))

	fe := linalg.dot(f, eyeVec)

    self.mat = {
		+s.x, +s.y, +s.z, -linalg.dot(s, eyeVec),
		+u.x, +u.y, +u.z, -linalg.dot(u, eyeVec),
		+f.x, +f.y, +f.z, -fe,
		   0,    0,    0, 1,
	}
}

Camera_Init :: proc (self:^Camera, eyeVec:linalg.Point3DF = {0,0,-1}, focusVec:linalg.Point3DF = {0,0,0}, upVec:linalg.Point3DF = {0,1,0}) {
    __Camera_Update(self, eyeVec, focusVec, upVec)
    __Camera_Init(self)
}

Camera_Update :: proc(self:^Camera, eyeVec:linalg.Point3DF = {0,0,-1}, focusVec:linalg.Point3DF = {0,0,0}, upVec:linalg.Point3DF = {0,0,1}) {
    __Camera_Update(self, eyeVec, focusVec, upVec)
    Camera_UpdateMatrixRaw(self, self.mat)
}