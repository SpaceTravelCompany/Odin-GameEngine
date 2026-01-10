package gui

import "base:intrinsics"
import "core:math"
import "core:math/linalg"
import ".."

// ============================================================================
// Type Definitions
// ============================================================================

pos_align_x :: enum {
    center,
    left,
    right,
}

pos_align_y :: enum {
    middle,
    top,
    bottom,
}

//do subtype to iobject
gui_component :: struct {
    gui_pos : linalg.PointF,
    gui_center_pt : linalg.PointF,
    gui_scale : linalg.PointF,
    gui_rotation : f32,
    gui_align_x : pos_align_x,
    gui_align_y : pos_align_y,
}

// ============================================================================
// GUI Component Management
// ============================================================================

@(require_results, private) __base_mat :: #force_inline proc "contextless" (self_component:^gui_component, mul: linalg.PointF) -> Maybe(linalg.Matrix) {
    return engine.sr_2d_matrix2(self_component.gui_scale, self_component.gui_rotation, self_component.gui_center_pt * mul)
}

/*
Initializes a GUI component with alignment and positioning

Inputs:
- self: Pointer to the object to initialize (must be a subtype of iobject)
- self_component: Pointer to the GUI component with positioning and alignment data

Returns:
- None
*/
 gui_component_init :: proc (self:^$T, self_component:^gui_component)
    where intrinsics.type_is_subtype_of(T, engine.iobject)  {
    
    window_width :f32 = 2.0 / self.projection.mat[0, 0]
    window_height :f32 = 2.0 / self.projection.mat[1, 1]
    
    base : Maybe(linalg.Matrix) = nil
    mat : linalg.Matrix

    switch self_component.gui_align_x {
        case .left:
            switch self_component.gui_align_y {
                case .top:
                    base = __base_mat(self_component, linalg.PointF{1.0, -1.0})
                    mat = engine.t_2d_matrix(linalg.Point3DF{-window_width / 2.0 + self_component.gui_pos.x, window_height / 2.0 - self_component.gui_pos.y, 0.0})
                case .middle:
                    base = __base_mat(self_component, linalg.PointF{1.0, 1.0})
                    mat = engine.t_2d_matrix(linalg.Point3DF{-window_width / 2.0 + self_component.gui_pos.x, self_component.gui_pos.y, 0.0})
                case .bottom:
                    base = __base_mat(self_component, linalg.PointF{1.0, 1.0})
                    mat = engine.t_2d_matrix(linalg.Point3DF{-window_width / 2.0 + self_component.gui_pos.x, -window_height / 2.0 + self_component.gui_pos.y, 0.0})     
            }
        case .center:
            switch self_component.gui_align_y {
                case .top:
                    base = __base_mat(self_component, linalg.PointF{1.0, -1.0})
                    mat = engine.t_2d_matrix(linalg.Point3DF{self_component.gui_pos.x, window_height / 2.0 - self_component.gui_pos.y, 0.0})
                case .middle:
                    base = __base_mat(self_component, linalg.PointF{1.0, 1.0})
                    mat = engine.t_2d_matrix(linalg.Point3DF{self_component.gui_pos.x, self_component.gui_pos.y, 0.0})
                case .bottom:
                    base = __base_mat(self_component, linalg.PointF{1.0, 1.0})
                    mat = engine.t_2d_matrix(linalg.Point3DF{self_component.gui_pos.x, -window_height / 2.0 + self_component.gui_pos.y, 0.0})     
            }
        case .right:
            switch self_component.gui_align_y {
                case .top:
                    base = __base_mat(self_component, linalg.PointF{-1.0, -1.0})
                    mat = engine.t_2d_matrix(linalg.Point3DF{window_width / 2.0 - self_component.gui_pos.x, window_height / 2.0 - self_component.gui_pos.y, 0.0})
                case .middle:
                    base = __base_mat(self_component, linalg.PointF{-1.0, 1.0})
                    mat = engine.t_2d_matrix(linalg.Point3DF{window_width / 2.0 - self_component.gui_pos.x, self_component.gui_pos.y, 0.0})
                case .bottom:
                    base = __base_mat(self_component, linalg.PointF{-1.0, 1.0})
                    mat = engine.t_2d_matrix(linalg.Point3DF{window_width / 2.0 - self_component.gui_pos.x, -window_height / 2.0 + self_component.gui_pos.y, 0.0})     
            }
    }

    self.mat = base != nil ? linalg.mul(mat, base.?) : mat
}

/*
Initializes a GUI component and updates its transform matrix

Inputs:
- self: Pointer to the object (must be a subtype of iobject)
- self_component: Pointer to the GUI component

Returns:
- None
*/
gui_component_size ::  proc (self:^$T, self_component:^gui_component)
    where intrinsics.type_is_subtype_of(T, engine.iobject) {
    gui_component_init(self, self_component)

    engine.iobject_update_transform_matrix(auto_cast self)
}

