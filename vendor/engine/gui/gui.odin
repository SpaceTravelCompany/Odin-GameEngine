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
    return engine.SR_2D_MATRIX2(self_component.gui_scale, self_component.gui_rotation, self_component.gui_center_pt * mul)
}

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
                    mat = engine.__T_2D_MATRIX(linalg.Point3DF{-window_width / 2.0 + self_component.gui_pos.x, window_height / 2.0 - self_component.gui_pos.y, 0.0})
                case .middle:
                    base = __base_mat(self_component, linalg.PointF{1.0, 1.0})
                    mat = engine.__T_2D_MATRIX(linalg.Point3DF{-window_width / 2.0 + self_component.gui_pos.x, self_component.gui_pos.y, 0.0})
                case .bottom:
                    base = __base_mat(self_component, linalg.PointF{1.0, 1.0})
                    mat = engine.__T_2D_MATRIX(linalg.Point3DF{-window_width / 2.0 + self_component.gui_pos.x, -window_height / 2.0 + self_component.gui_pos.y, 0.0})     
            }
        case .center:
            switch self_component.gui_align_y {
                case .top:
                    base = __base_mat(self_component, linalg.PointF{1.0, -1.0})
                    mat = engine.__T_2D_MATRIX(linalg.Point3DF{self_component.gui_pos.x, window_height / 2.0 - self_component.gui_pos.y, 0.0})
                case .middle:
                    base = __base_mat(self_component, linalg.PointF{1.0, 1.0})
                    mat = engine.__T_2D_MATRIX(linalg.Point3DF{self_component.gui_pos.x, self_component.gui_pos.y, 0.0})
                case .bottom:
                    base = __base_mat(self_component, linalg.PointF{1.0, 1.0})
                    mat = engine.__T_2D_MATRIX(linalg.Point3DF{self_component.gui_pos.x, -window_height / 2.0 + self_component.gui_pos.y, 0.0})     
            }
        case .right:
            switch self_component.gui_align_y {
                case .top:
                    base = __base_mat(self_component, linalg.PointF{-1.0, -1.0})
                    mat = engine.__T_2D_MATRIX(linalg.Point3DF{window_width / 2.0 - self_component.gui_pos.x, window_height / 2.0 - self_component.gui_pos.y, 0.0})
                case .middle:
                    base = __base_mat(self_component, linalg.PointF{-1.0, 1.0})
                    mat = engine.__T_2D_MATRIX(linalg.Point3DF{window_width / 2.0 - self_component.gui_pos.x, self_component.gui_pos.y, 0.0})
                case .bottom:
                    base = __base_mat(self_component, linalg.PointF{-1.0, 1.0})
                    mat = engine.__T_2D_MATRIX(linalg.Point3DF{window_width / 2.0 - self_component.gui_pos.x, -window_height / 2.0 + self_component.gui_pos.y, 0.0})     
            }
    }

    self.mat = base != nil ? linalg.mul(mat, base.?) : mat
}

gui_component_size ::  proc (self:^$T, self_component:^gui_component)
    where intrinsics.type_is_subtype_of(T, engine.iobject) {
    gui_component_init(self, self_component)

    engine.iobject_update_transform_matrix(auto_cast self)
}

