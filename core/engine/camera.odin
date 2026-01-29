package engine

import "base:intrinsics"
import "core:mem"
import "core:math/linalg"

/*
Camera structure for view matrix management

Contains the view matrix and uniform buffer for rendering
*/
camera :: struct {
    using _: __matrix_in,
}

/*
Initializes a camera with the specified view parameters

Inputs:
- self: Pointer to the camera to initialize
- eye_vec: The position of the camera (default: {0, 0, -1})
- focus_vec: The point the camera is looking at (default: {0, 0, 0})
- up_vec: The up vector for the camera (default: {0, 1, 0})

Returns:
- None
*/
camera_init :: proc (self:^camera, eye_vec:linalg.point3d = {0,0,-1}, focus_vec:linalg.point3d = {0,0,0}, up_vec:linalg.point3d = {0,1,0}) {
    __camera_update(self, eye_vec, focus_vec, up_vec)
    __camera_init(self)
}

/*
Initializes a camera with a raw matrix

Inputs:
- self: Pointer to the camera to initialize
- mat: The view matrix to use

Returns:
- None
*/
camera_init_matrix_raw :: proc (self:^camera, mat:linalg.matrix44) {
    self.mat = mat
    __camera_init(self)
}

@private __camera_init :: #force_inline proc(self:^camera) {
    buffer_resource_create_buffer(self, {
        size = size_of(linalg.matrix44),
        type = .UNIFORM,
        resource_usage = .CPU,
    }, mem.ptr_to_bytes(&self.mat), true)
}

/*
Updates the camera view matrix with new parameters

Inputs:
- self: Pointer to the camera to update
- eye_vec: The new position of the camera (default: {0, 0, -1})
- focus_vec: The new point the camera is looking at (default: {0, 0, 0})
- up_vec: The new up vector for the camera (default: {0, 0, 1})

Returns:
- None
*/
camera_update :: proc(self:^camera, eye_vec:linalg.point3d = {0,0,-1}, focus_vec:linalg.point3d = {0,0,0}, up_vec:linalg.point3d = {0,0,1}) {
    __camera_update(self, eye_vec, focus_vec, up_vec)
    camera_update_matrix_raw(self, self.mat)
}

/*
Updates the camera with a raw matrix

Inputs:
- self: Pointer to the camera to update
- _mat: The new view matrix

Returns:
- None
*/
camera_update_matrix_raw :: proc(self:^camera, _mat:linalg.matrix44) {
    self.mat = _mat
    buffer_resource_copy_update(self, &self.mat)
}

@private __camera_update :: #force_inline proc(self:^camera, eye_vec:linalg.point3d, focus_vec:linalg.point3d, up_vec:linalg.point3d = {0,0,1}) {
    f := linalg.normalize(focus_vec - eye_vec)
	s := linalg.normalize(linalg.cross(up_vec, f))
	u := linalg.normalize(linalg.cross(f, s))

	fe := linalg.dot(f, eye_vec)

    self.mat = {
		+s.x, +s.y, +s.z, -linalg.dot(s, eye_vec),
		+u.x, +u.y, +u.z, -linalg.dot(u, eye_vec),
		+f.x, +f.y, +f.z, -fe,
		   0,    0,    0, 1,
	}
}

/*
Deinitializes and cleans up camera resources

Inputs:
- self: Pointer to the camera to deinitialize

Returns:
- None
*/
camera_deinit :: proc(self:^camera) {
    buffer_resource_deinit(self)
}

/*
Returns a pointer to the default camera

Returns:
- Pointer to the default camera
*/
def_camera :: proc() -> ^camera {
    return &__g_default_camera
}
