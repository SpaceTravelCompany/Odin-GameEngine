package engine

import "core:math"
import "core:mem"
import "core:slice"
import "core:sync"
import "core:math/linalg"
import "base:intrinsics"
import "base:runtime"
import vk "vendor:vulkan"
import "graphics_api"

Projection :: struct {
    using _: __MatrixIn,
}

Projection_InitMatrixOrtho :: proc (self:^Projection, left:f32, right:f32, bottom:f32, top:f32, near:f32 = 0.1, far:f32 = 100, flipZAxisForVulkan := true) {
    __Projection_UpdateOrtho(self, left, right, bottom, top, near, far, flipZAxisForVulkan)
    __Projection_Init(self)
}

Projection_InitMatrixOrthoWindow :: proc (self:^Projection, width:f32, height:f32, near:f32 = 0.1, far:f32 = 100, flipZAxisForVulkan := true) {
    __Projection_UpdateOrthoWindow(self, width, height, near, far, flipZAxisForVulkan)
    __Projection_Init(self)
}

@private __Projection_UpdateOrtho :: #force_inline proc(self:^Projection, left:f32, right:f32, bottom:f32, top:f32, near:f32 = 0.1, far:f32 = 100, flipZAxisForVulkan := true) {
    self.mat = linalg.matrix_ortho3d_f32(left, right, bottom, top, near, far, flipZAxisForVulkan)
}

Projection_UpdateOrtho :: #force_inline proc(self:^Projection,  left:f32, right:f32, bottom:f32, top:f32, near:f32 = 0.1, far:f32 = 100, flipZAxisForVulkan := true) {
    __Projection_UpdateOrtho(self, left, right, bottom, top, near, far, flipZAxisForVulkan)
    Projection_UpdateMatrixRaw(self, self.mat)
}

@private __Projection_UpdateOrthoWindow :: #force_inline proc(self:^Projection, width:f32, height:f32, near:f32 = 0.1, far:f32 = 100, flipAxisForVulkan := true) {
    windowWidthF := f32(graphics_api.__windowWidth.?)
    windowHeightF := f32(graphics_api.__windowHeight.?)
    ratio := windowWidthF / windowHeightF > width / height ? height / windowHeightF : width / windowWidthF

    windowWidthF *= ratio
    windowHeightF *= ratio

    self.mat = {
        2.0 / windowWidthF, 0, 0, 0,
        0, 2.0 / windowHeightF, 0, 0,
        0, 0, 1 / (far - near), -near / (far - near),
        0, 0, 0, 1,
    }
    if flipAxisForVulkan {
        self.mat[1,1] = -self.mat[1,1]
    }
}

Projection_UpdateOrthoWindow :: #force_inline proc(self:^Projection, width:f32, height:f32, near:f32 = 0.1, far:f32 = 100, flipZAxisForVulkan := true) {
    __Projection_UpdateOrthoWindow(self, width, height, near, far, flipZAxisForVulkan)
    Projection_UpdateMatrixRaw(self, self.mat)
}

Projection_InitMatrixRaw :: proc (self:^Projection, mat:linalg.Matrix) {
    self.mat = mat

    __Projection_Init(self)
}


//! aspect is 0 means use window aspect
Projection_InitMatrixPerspective :: proc (self:^Projection, fov:f32, aspect:f32 = 0, near:f32 = 0.1, far:f32 = 100, flipZAxisForVulkan := true) {
    __Projection_UpdatePerspective(self, fov, aspect, near, far, flipZAxisForVulkan)
    __Projection_Init(self)
}

@private __Projection_UpdatePerspective :: #force_inline proc(self:^Projection, fov:f32, aspect:f32 = 0, near:f32 = 0.1, far:f32 = 100, flipAxisForVulkan := true) {
    aspectF := aspect
    if aspectF == 0 do aspectF = f32(graphics_api.__windowWidth.?) / f32(graphics_api.__windowHeight.?)
    sfov :f32 = math.sin(0.5 * fov)
    cfov :f32 = math.cos(0.5 * fov)

    h := cfov / sfov
    w := h / aspectF
    r := far / (far - near)
    self.mat = {
         w, 0, 0, 0,
         0, h, 0, 0,
         0, 0, r, -r * near,
         0, 0, 1, 0,
    };
    if flipAxisForVulkan {
        self.mat[1,1] = -self.mat[1,1]
    }
}

Projection_UpdatePerspective :: #force_inline proc(self:^Projection, fov:f32, aspect:f32 = 0, near:f32 = 0.1, far:f32 = 100, flipAxisForVulkan := true) {
    __Projection_UpdatePerspective(self, fov, aspect, near, far, flipAxisForVulkan)
    Projection_UpdateMatrixRaw(self, self.mat)
}

//? uniform object is all small, so use_gcpu_mem is true by default
@private __Projection_Init :: #force_inline proc(self:^Projection) {
    mem.ICheckInit_Init(&self.checkInit)
    mat : linalg.Matrix
    when is_mobile {
        mat = linalg.matrix_mul(vkRotationMatrix, self.mat)
    } else {
        mat = self.mat
    }
    graphics_api.BufferResource_CreateBuffer(&self.matUniform, {
        len = size_of(linalg.Matrix),
        type = .UNIFORM,
        resourceUsage = .CPU,
        single = false,
    }, mem.ptr_to_bytes(&mat), true)
}

Projection_Deinit :: proc(self:^Projection) {
    mem.ICheckInit_Deinit(&self.checkInit)
    graphics_api.BufferResource_Deinit(&self.matUniform)
}

Projection_UpdateMatrixRaw :: proc(self:^Projection, _mat:linalg.Matrix) {
    mem.ICheckInit_Check(&self.checkInit)
    mat : linalg.Matrix
    when is_mobile {
        mat = linalg.matrix_mul(vkRotationMatrix, _mat)
    } else {
        mat = _mat
    }
    self.mat = _mat
    graphics_api.BufferResource_CopyUpdate(&self.matUniform, &mat)
}
