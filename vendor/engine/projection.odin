package engine

import "core:math"
import "core:mem"
import "core:slice"
import "core:sync"
import "core:math/linalg"
import "base:intrinsics"
import "base:runtime"
import vk "vendor:vulkan"


projection :: struct {
    using _: __matrix_in,
}

projection_init_matrix_ortho :: proc (self:^projection, left:f32, right:f32, bottom:f32, top:f32, near:f32 = 0.1, far:f32 = 100, flip_z_axis_for_vulkan := true) {
    __projection_update_ortho(self, left, right, bottom, top, near, far, flip_z_axis_for_vulkan)
    __projection_init(self)
}

projection_init_matrix_ortho_window :: proc (self:^projection, width:f32, height:f32, near:f32 = 0.1, far:f32 = 100, flip_z_axis_for_vulkan := true) {
    __projection_update_ortho_window(self, width, height, near, far, flip_z_axis_for_vulkan)
    __projection_init(self)
}

@private __projection_update_ortho :: #force_inline proc(self:^projection, left:f32, right:f32, bottom:f32, top:f32, near:f32 = 0.1, far:f32 = 100, flip_z_axis_for_vulkan := true) {
    self.mat = linalg.matrix_ortho3d_f32(left, right, bottom, top, near, far, flip_z_axis_for_vulkan)
}

projection_update_ortho :: #force_inline proc(self:^projection,  left:f32, right:f32, bottom:f32, top:f32, near:f32 = 0.1, far:f32 = 100, flip_z_axis_for_vulkan := true) {
    __projection_update_ortho(self, left, right, bottom, top, near, far, flip_z_axis_for_vulkan)
    projection_update_matrix_raw(self, self.mat)
}

@private __projection_update_ortho_window :: #force_inline proc(self:^projection, width:f32, height:f32, near:f32 = 0.1, far:f32 = 100, flip_axis_for_vulkan := true) {
    window_width_f := f32(__window_width.?)
    window_height_f := f32(__window_height.?)
    ratio := window_width_f / window_height_f > width / height ? height / window_height_f : width / window_width_f

    window_width_f *= ratio
    window_height_f *= ratio

    self.mat = {
        2.0 / window_width_f, 0, 0, 0,
        0, 2.0 / window_height_f, 0, 0,
        0, 0, 1 / (far - near), -near / (far - near),
        0, 0, 0, 1,
    }
    if flip_axis_for_vulkan {
        self.mat[1,1] = -self.mat[1,1]
    }
}

projection_update_ortho_window :: #force_inline proc(self:^projection, width:f32, height:f32, near:f32 = 0.1, far:f32 = 100, flip_z_axis_for_vulkan := true) {
    __projection_update_ortho_window(self, width, height, near, far, flip_z_axis_for_vulkan)
    projection_update_matrix_raw(self, self.mat)
}

projection_init_matrix_raw :: proc (self:^projection, mat:linalg.Matrix) {
    self.mat = mat

    __projection_init(self)
}


//! aspect is 0 means use window aspect
projection_init_matrix_perspective :: proc (self:^projection, fov:f32, aspect:f32 = 0, near:f32 = 0.1, far:f32 = 100, flip_z_axis_for_vulkan := true) {
    __projection_update_perspective(self, fov, aspect, near, far, flip_z_axis_for_vulkan)
    __projection_init(self)
}

@private __projection_update_perspective :: #force_inline proc(self:^projection, fov:f32, aspect:f32 = 0, near:f32 = 0.1, far:f32 = 100, flip_axis_for_vulkan := true) {
    aspect_f := aspect
    if aspect_f == 0 do aspect_f = f32(__window_width.?) / f32(__window_height.?)
    sfov :f32 = math.sin(0.5 * fov)
    cfov :f32 = math.cos(0.5 * fov)

    h := cfov / sfov
    w := h / aspect_f
    r := far / (far - near)
    self.mat = {
         w, 0, 0, 0,
         0, h, 0, 0,
         0, 0, r, -r * near,
         0, 0, 1, 0,
    };
    if flip_axis_for_vulkan {
        self.mat[1,1] = -self.mat[1,1]
    }
}

projection_update_perspective :: #force_inline proc(self:^projection, fov:f32, aspect:f32 = 0, near:f32 = 0.1, far:f32 = 100, flip_axis_for_vulkan := true) {
    __projection_update_perspective(self, fov, aspect, near, far, flip_axis_for_vulkan)
    projection_update_matrix_raw(self, self.mat)
}

//? uniform object is all small, so use_gcpu_mem is true by default
@private __projection_init :: #force_inline proc(self:^projection) {
    mem.ICheckInit_Init(&self.check_init)
    mat : linalg.Matrix
    when is_mobile {
        mat = linalg.matrix_mul(rotation_matrix, self.mat)
    } else {
        mat = self.mat
    }
    buffer_resource_create_buffer(&self.mat_uniform, {
        len = size_of(linalg.Matrix),
        type = .UNIFORM,
        resource_usage = .CPU,
        single = false,
    }, mem.ptr_to_bytes(&mat), true)
}

projection_deinit :: proc(self:^projection) {
    mem.ICheckInit_Deinit(&self.check_init)

    clone_mat_uniform := new(buffer_resource, temp_arena_allocator)
    clone_mat_uniform^ = self.mat_uniform
    buffer_resource_deinit(clone_mat_uniform)
}

projection_update_matrix_raw :: proc(self:^projection, _mat:linalg.Matrix) {
    mem.ICheckInit_Check(&self.check_init)
    mat : linalg.Matrix
    when is_mobile {
        mat = linalg.matrix_mul(rotation_matrix, _mat)
    } else {
        mat = _mat
    }
    self.mat = _mat
    buffer_resource_copy_update(&self.mat_uniform, &mat)
}
