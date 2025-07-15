package geometry

import "core:math"
import "core:slice"
import "core:fmt"
import "core:mem"
import "core:debug/trace"
import "core:math/linalg"
import "base:runtime"
import "base:intrinsics"
import "core:math/poly2tri"


ShapeVertex2D :: struct #align(1) {
    pos: linalg.PointF,
    uvw: linalg.Point3DF,
    color: linalg.Point3DwF,
};

RawShape :: struct {
    vertices : []ShapeVertex2D,
    indices:[]u32,
    rect:linalg.RectF,
}

CurveType :: enum {
    Line,
    Unknown,
    Serpentine,
    Loop,
    Cusp,
    Quadratic,
}

// LineError :: enum {
//     None,
//     IsPointNotLine,
//     IsNotCurve,
//     InvaildLine,
//     OutOfIdx,    
// }

ShapesError :: enum {
    None,
    Edge_P1_Equal_P2,
    Triangle_MarkNeighbor2_target_not_a_neighbor,
    Triangle_PointCW_point_not_in_triangle,
    Triangle_PointCCW_point_not_in_triangle,
    Triangle_Index_point_not_in_triangle,
    Triangle_Legalize_opoint_not_in_triangle,
    AdvancingFront_LocatePoint_point_not_found,
    EdgeEvent2_nil_triangle,
    EdgeEvent2_collinear_points_not_supported,
    FlipEdgeEvent_nil_triangle,
    FlipEdgeEvent_nil_neighbor_across,
    Opposing_point_on_constrained_edge,//!Unsupported
    FlipScanEdgeEvent_nil_neighbor_across,
    FlipScanEdgeEvent_nil_opposing_point,
    FlipScanEdgeEvent_nil_on_either_of_points,
    nil_node,

    IsPointNotLine,
    IsNotCurve,
    InvaildLine,
    OutOfIdx,
    IsNotPolygon,
    invaildPolygonLineCounts,
    CantPolygonMatchHoles,

    EmptyPolygon,
}

// Line :: struct {
//     start:PointF,
//     control0:PointF,
//     control1:PointF,
//     type:CurveType,
// }

// Line_LineInit :: #force_inline proc "contextless" (start:PointF) -> Line {
//     return {
//         start = start,
//         type = .Line
//     }
// }
// Line_QuadraticInit :: #force_inline proc "contextless" (start:PointF, control:PointF) -> Line {
//     return {
//         start = start,
//         control0 = control,
//         control1 = control,
//         type = .Quadratic
//     }
// }


Shapes :: struct {
    poly:[]linalg.PointF,
    nPolys:[]u32,
    nTypes:[]u32,
    types:[]CurveType,
    colors:[]linalg.Point3DwF,
    // strokeColors:[]linalg.Point3DwF,
    // thickness:[]f32,
}

CvtQuadraticToCubic0 :: #force_inline proc "contextless" (_start : linalg.PointF, _control : linalg.PointF) -> linalg.PointF {
    return linalg.PointF{ _start.x + (2.0/3.0) * (_control.x - _start.x), _start.y + (2.0/3.0) * (_control.y - _start.y) }
}
CvtQuadraticToCubic1 :: #force_inline proc "contextless" (_end : linalg.PointF, _control : linalg.PointF) -> linalg.PointF {
    return CvtQuadraticToCubic0(_end, _control)
}


RawShape_Free :: proc (self:^RawShape, allocator := context.allocator) {
    delete(self.vertices, allocator)
    delete(self.indices, allocator)
    free(self, allocator)
}

RawShape_Clone :: proc (self:^RawShape, allocator := context.allocator) -> (res:^RawShape = nil) {
    res = new(RawShape, allocator)
    res.vertices = mem.make_non_zeroed_slice([]ShapeVertex2D, len(self.vertices), allocator)
    res.indices = mem.make_non_zeroed_slice([]u32, len(self.indices), allocator)
    intrinsics.mem_copy_non_overlapping(&res.vertices[0], &self.vertices[0], len(self.vertices) * size_of(ShapeVertex2D))
    intrinsics.mem_copy_non_overlapping(&res.indices[0], &self.indices[0], len(self.indices) * size_of(u32))

    res.rect = self.rect
    return
}


GetCubicCurveType :: proc "contextless" (_start:[2]$T, _control0:[2]T, _control1:[2]T, _end:[2]T) ->
(type:CurveType = .Unknown, err:ShapesError = .None, outD:[3]T) where intrinsics.type_is_float(T) {

    if _start == _control0 && _control0 == _control1 && _control1 == _end {
        err = .IsPointNotLine
        return
    }

    cross_1 := [3]T{_end.y - _control1.y,       _control1.x - _end.x,       _end.x * _control1.y - _end.y * _control1.x}
    cross_2 := [3]T{_start.y - _end.y,          _end.x - _start.x,          _start.x * _end.y - _start.y * _end.x}
    cross_3 := [3]T{_control0.y - _start.y,     _start.x - _control0.x,     _control0.x * _start.y - _control0.y * _start.x}

    a1 := _start.x * cross_1.x      + _start.y * cross_1.y      + cross_1.z
    a2 := _control0.x * cross_2.x   + _control0.y * cross_2.y   + cross_2.z
    a3 := _control1.x * cross_3.x   + _control1.y * cross_3.y   + cross_3.z

    outD[0] = a1 - 2 * a2 + 3 * a3
    outD[1] = -a2 + 3 * a3
    outD[2] = 3 * a3

    D := 3 * outD[1] * outD[1] - 4 * outD[2] * outD[0]
    discr := outD[0] * outD[0] * D

    if discr >= 0 - math.epsilon(T) && discr <= 0 + math.epsilon(T) {
        if outD[0] == 0.0 && outD[1] == 0.0 {
            if outD[2] == 0.0 {
                type = .Line
                return
            }
            type = .Quadratic
            return
        }
        type = .Cusp
        return
    }
    if discr > 0 {
        type = .Serpentine
        return
    }
    type = .Loop
    return
}

LineSplitCubic :: proc "contextless" (pts:[4][$N]$T, t:T) -> (outPts1:[4][N]T, outPts2:[4][N]T) where intrinsics.type_is_float(T) {
    outPts1[0] = pts[0]
    outPts2[3] = pts[3]
    outPts1[1] = linalg.lerp(pts[0], pts[1], t)
    outPts2[2] = linalg.lerp(pts[2], pts[3], t)
    p11 := linalg.lerp(pts[1], pts[2], t)
    outPts1[2] = linalg.lerp(outPts1[1], p11, t)
    outPts2[1] = linalg.lerp(p11, outPts2[2], t)
    outPts1[3] = linalg.lerp(outPts1[2], outPts2[1], t)
    outPts2[0] = outPts1[3]
    return
}

LineSplitQuadratic :: proc "contextless" (pts:[3][$N]$T, t:T) -> (outPts1:[3][N]T, outPts2:[3][N]T) where intrinsics.type_is_float(T) {
    outPts1[0] = pts[0]
    outPts2[2] = pts[2]
    outPts1[1] = linalg.lerp(pts[0], pts[1], t)
    outPts2[1] = linalg.lerp(pts[1], pts[2], t)
    outPts1[2] = pts[1]
    outPts2[0] = pts[1]
    return
}

LineSplitLine :: proc "contextless" (pts:[2][$N]$T, t:T) -> (outPts1:[2][N]T, outPts2:[2][N]T) where intrinsics.type_is_float(T) {
    outPts1[0] = pts[0]
    outPts1[1] = linalg.lerp(pts[0], pts[1], t)
    outPts2[0] = outPts1[1]
    outPts2[1] = pts[1]
    return
}

@(private="file") _Shapes_ComputeLine :: proc(
    vertList:^[dynamic]ShapeVertex2D,
    indList:^[dynamic]u32,
    outPoly:^[dynamic]CurveStruct,
    color:linalg.Point3DwF,
    pts:[]linalg.PointF,
    type:CurveType,
    _subdiv :f32 = 0.0,
    _repeat :int = -1) -> ShapesError {

    if _subdiv < 0 do trace.panic_log("_subdiv can't negative.")

    curveType := type
    err:ShapesError = .None

    pts2 : [4][2]f32
    pts_:[4][2]f32
    intrinsics.mem_copy_non_overlapping(&pts_[0], &pts[0], len(pts) * size_of(linalg.PointF))

    reverse := false
    outD:[3]f32 = {0, 0, 0}
    if curveType != .Line && curveType != .Quadratic {
        curveType, err, outD = GetCubicCurveType(pts[0], pts[1], pts[2], pts[3])
        if err != .None do return err
    } else if curveType == .Quadratic {
        if _subdiv == 0.0 {
            vlen :u32 = u32(len(vertList))
            if linalg.GetPolygonOrientation(pts) == .CounterClockwise {
                non_zero_append(vertList, ShapeVertex2D{
                    uvw = {0,0,0},
                    pos = pts[0],
                    color = color,
                })
                non_zero_append(vertList, ShapeVertex2D{
                    uvw = {-0.5,0,0.5},
                    pos = pts[1],
                    color = color,
                })
                non_zero_append(vertList, ShapeVertex2D{
                    uvw = {-1,-1,1},
                    pos = pts[2],
                    color = color,
                })
            } else {
                non_zero_append(vertList, ShapeVertex2D{
                    uvw = {0,0,0},
                    pos = pts[0],
                    color = color,
                })
                non_zero_append(vertList, ShapeVertex2D{
                    uvw = {0.5,0,0.5},
                    pos = pts[1],
                    color = color,
                })
                non_zero_append(vertList, ShapeVertex2D{
                    uvw = {1,1,1},
                    pos = pts[2],
                    color = color,
                })
            }
    
            non_zero_append(indList, vlen, vlen + 1, vlen + 2)
    
            non_zero_append(outPoly, CurveStruct{pts[0], false}, CurveStruct{pts[1], true})
        } else {
            x01 := (pts[1].x - pts[0].x) * _subdiv + pts[0].x
            y01 := (pts[1].y - pts[0].y) * _subdiv + pts[0].y
            x12 := (pts[2].x - pts[1].x) * _subdiv + pts[1].x
            y12 := (pts[2].y - pts[1].y) * _subdiv + pts[1].y

            x012 := (x12 - x01) * _subdiv + x01
            y012 := (y12 - y01) * _subdiv + y01

            err := _Shapes_ComputeLine(vertList, indList, outPoly, color,{pts[0], { x01, y01 }, { x012, y012 }}, .Quadratic, 0.0, 0)
            if err != .None do return err
            err = _Shapes_ComputeLine(vertList, indList, outPoly, color,{{ x012, y012 }, { x12, y12 }, pts[2]}, .Quadratic,0.0, 0)
            if err != .None do return err
        }
        return .None
    }

    F :matrix[4,4]f32

    reverseOrientation :: #force_inline proc "contextless" (F:matrix[4,4]f32) -> matrix[4,4]f32 {
        return {
            -F[0,0], -F[0,1], F[0,2], F[0,3],
            -F[1,0], -F[1,1], F[1,2], F[1,3],
            -F[2,0], -F[2,1], F[2,2], F[2,3],
            -F[3,0], -F[3,1], F[3,2], F[3,3],
        }
    }
    repeat := 0
    subdiv :f32 = 0.0

    if _subdiv == 0.0 {
        switch curveType {
            case .Line:
                non_zero_append(outPoly, CurveStruct{pts[0], false})
                return .None
            case .Quadratic:
                F = {
                    0,              0,              0,          0,
                    1.0/3.0,        0,              1.0/3.0,    0,
                    2.0/3.0,        1.0/3.0,        2.0/3.0,    0,
                    1,              1,              1,          1,
                }
                if outD[2] < 0 do reverse = true
            case .Serpentine:
                t1 := math.sqrt_f32(9.0 * outD[1] * outD[1] - 12 * outD[0] * outD[2])
                ls := 3.0 * outD[1] - t1
                lt := 6.0 * outD[0]
                ms := 3.0 * outD[1] + t1
                mt := lt
                ltMinusLs := lt - ls
                mtMinusMs := mt - ms
    
                F = {
                    ls * ms,                                                            ls * ls * ls,                           ms * ms * ms,           0,
                    (1.0 / 3.0) * (3.0 * ls * ms - ls * mt - lt * ms),                  ls * ls * (ls - lt),                    ms * ms * (ms - mt),    0,
                    (1.0 / 3.0) * (lt * (mt - 2.0 * ms) + ls * (3.0 * ms - 2.0 * mt)),  ltMinusLs * ltMinusLs * ls,             mtMinusMs * mtMinusMs * ms,             0,
                    ltMinusLs * mtMinusMs,                                              -(ltMinusLs * ltMinusLs * ltMinusLs),   -(mtMinusMs * mtMinusMs * mtMinusMs),   1,
                }
    
                if outD[0] < 0.0 do reverse = true
            case .Loop:
                t1 := math.sqrt_f32(4 * outD[0] * outD[2] - 3 * outD[1] * outD[1])
                ls := outD[1] - t1
                lt := 2 * outD[0]
                ms := outD[1] + t1
                mt := lt
    
                ql := ls / lt
                qm := ms / mt
               
                if _repeat == -1 && 0.0 < ql && ql < 1.0 {
                    repeat = 1
                    subdiv = ql
                } else if _repeat == -1 && 0.0 < qm && qm < 1.0 {
                    repeat = 2
                    subdiv = qm
                } else {
                    ltMinusLs := lt - ls
                    mtMinusMs := mt - ms
    
                    F = {
                        ls * ms,                                                            ls * ls * ms,                           ls * ms * ms,           0,
                        (1.0/3.0) * (-ls * mt - lt * ms + 3.0 * ls * ms),
                        -(1.0 / 3.0) * ls * (ls * (mt - 3.0 * ms) + 2.0 * lt * ms),
                        -(1.0 / 3.0) * ms * (ls * (2.0 * mt - 3.0 * ms) + lt * ms),    0,
                        (1.0/3.0) * (lt * (mt - 2.0 * ms) + ls * (3.0 * ms - 2.0 * mt)),
                        (1.0/3.0) * ltMinusLs * (ls * (2.0 * mt - 3.0 * ms) + lt * ms),
                        (1.0/3.0) * mtMinusMs * (ls * (mt - 3.0 * ms) + 2.0 * lt * ms),   0,
                        ltMinusLs * mtMinusMs,  -(ltMinusLs * ltMinusLs) * mtMinusMs,   -ltMinusLs * mtMinusMs * mtMinusMs, 1,
                    }
          
                    reverse = (outD[0] > 0.0 && F[1,0] < 0.0) || (outD[0] < 0.0 && F[1,0] > 0.0)
                }
            case .Cusp:
                ls := outD[2]
                lt := 3.0 * outD[1]
                lsMinusLt := ls - lt
                F = {
                    ls,                         ls * ls * ls,                       1,  0,
                    (ls - (1.0 / 3.0) * lt),    ls * ls * lsMinusLt,                1,  0,
                    ls - (2.0 / 3.0) * lt,      lsMinusLt * lsMinusLt * ls,         1,  0,
                    lsMinusLt,                  lsMinusLt * lsMinusLt * lsMinusLt,  1,  1,
                }
                //reverse = true
            case .Unknown:
                trace.panic_log("GetCubicCurveType: unknown curve type")
        }
    }
   

    if repeat > 0 || _subdiv != 0.0 {
        //!X no need Quadratic
        if subdiv == 0.0 {
            subdiv = _subdiv
        }
        x01 := (pts[1].x - pts[0].x) * subdiv + pts[0].x
        y01 := (pts[1].y - pts[0].y) * subdiv + pts[0].y
        x12 := (pts[2].x - pts[1].x) * subdiv + pts[1].x
        y12 := (pts[2].y - pts[1].y) * subdiv + pts[1].y

        x23 := (pts[3].x - pts[2].x) * subdiv + pts[2].x
        y23 := (pts[3].y - pts[2].y) * subdiv + pts[2].y

        x012 := (x12 - x01) * subdiv + x01
        y012 := (y12 - y01) * subdiv + y01

        x123 := (x23 - x12) * subdiv + x12
        y123 := (y23 - y12) * subdiv + y12

        x0123 := (x123 - x012) * subdiv + x012
        y0123 := (y123 - y012) * subdiv + y012

        if repeat == 2 {
            err := _Shapes_ComputeLine(vertList, indList, outPoly, color,{pts[0], { x01, y01 }, { x012, y012 }, { x0123, y0123 }}, type, 0.0, 1)
            if err != .None do return err
            err = _Shapes_ComputeLine(vertList, indList, outPoly, color,{{ x0123, y0123 }, { x123, y123 }, { x23, y23 }, pts[3]}, type, 0.0, 0)
            if err != .None do return err
        } else if repeat == 1 {
            err := _Shapes_ComputeLine(vertList, indList, outPoly, color,{pts[0], { x01, y01 }, { x012, y012 }, { x0123, y0123 }}, type, 0.0, 0)
            if err != .None do return err
            err = _Shapes_ComputeLine(vertList, indList, outPoly, color,{{ x0123, y0123 }, { x123, y123 }, { x23, y23 }, pts[3]}, type, 0.0, 1)
            if err != .None do return err
        } else {
            if _repeat == 3 {
                err := _Shapes_ComputeLine(vertList, indList, outPoly, color,{pts[0], { x01, y01 }, { x012, y012 }, { x0123, y0123 }}, type, 0.0, 0)
                if err != .None do return err
                err = _Shapes_ComputeLine(vertList, indList, outPoly, color,{{ x0123, y0123 }, { x123, y123 }, { x23, y23 }, pts[3]}, type, 0.0, 0)
                if err != .None do return err
            } else {
                err := _Shapes_ComputeLine(vertList, indList, outPoly, color,{pts[0], { x01, y01 }, { x012, y012 }, { x0123, y0123 }}, type, 0.5, 3)
                if err != .None do return err
                err = _Shapes_ComputeLine(vertList, indList, outPoly, color,{{ x0123, y0123 }, { x123, y123 }, { x23, y23 }, pts[3]}, type, 0.5, 3)
                if err != .None do return err
            }
        }
        return .None
    }
    if repeat == 1 {
        reverse = !reverse
    }

    if reverse {
      F = reverseOrientation(F)
    }

    appendLine :: proc (vertList:^[dynamic]ShapeVertex2D, indList:^[dynamic]u32, color:linalg.Point3DwF, pts:[]linalg.PointF, F:matrix[4,4]f32) {
        if len(pts) == 2 {
            return
        }
        start :u32 = u32(len(vertList))
        non_zero_append(vertList, ShapeVertex2D{
            uvw = {F[0,0], F[0,1], F[0,2]},
            color = color,
        })
        non_zero_append(vertList, ShapeVertex2D{
            uvw = {F[1,0], F[1,1], F[1,2]},
            color = color,
        })
        non_zero_append(vertList, ShapeVertex2D{
            uvw = {F[2,0], F[2,1], F[2,2]},
            color = color,
        })
        non_zero_append(vertList, ShapeVertex2D{
            uvw = {F[3,0], F[3,1], F[3,2]},
            color = color,
        })
        if len(pts) == 3 {
            vertList[start].pos = pts[0]
            vertList[start+1].pos = CvtQuadraticToCubic0(pts[0], pts[1])
            vertList[start+2].pos = CvtQuadraticToCubic1(pts[2], pts[1])
            vertList[start+3].pos = pts[2]
        } else {// 4
            vertList[start].pos = pts[0]
            vertList[start+1].pos = pts[1]
            vertList[start+2].pos = pts[2]
            vertList[start+3].pos = pts[3]
        }
        //triangulate
        for i:u32 = 0; i < 4; i += 1 {
            for j:u32 = i + 1; j < 4; j += 1 {
                if vertList[start + i].pos == vertList[start + j].pos {
                    indices :[3]u32 = {start, start, start}
                    idx:u32 = 0
                    for k:u32 = 0; k < 4; k += 1 {
                        if k != j {
                            indices[idx] += k
                            idx += 1
                        }
                    }
                    non_zero_append(indList, ..indices[:])
                    return
                } 
            }
        }
        for i:u32 = 0; i < 4; i += 1 {
            indices :[3]u32 = {start, start, start}
            idx:u32 = 0
            for j:u32 = 0; j < 4; j += 1 {
                if j != i {
                    indices[idx] += j
                    idx += 1
                }
            }
            if linalg.PointInTriangle(vertList[start + i].pos, vertList[indices[0]].pos, vertList[indices[1]].pos, vertList[indices[2]].pos) {
                for k:u32 = 0; k < 3; k += 1 {
                    non_zero_append(indList, indices[k])
                    non_zero_append(indList, indices[(k + 1)%3])
                    non_zero_append(indList, start + i)
                }
                return
            }
        }

        b := linalg.LinesIntersect(vertList[start].pos, vertList[start + 2].pos, vertList[start + 1].pos, vertList[start + 3].pos)
        if b {
            if linalg.length2(vertList[start + 2].pos - vertList[start].pos) < linalg.length2(vertList[start + 3].pos - vertList[start + 1].pos) {
                non_zero_append(indList, start, start + 1, start + 2, start, start + 2, start + 3)
            } else {
                non_zero_append(indList, start, start + 1, start + 3, start + 1, start + 2, start + 3)
            }
            return
        }
        b = linalg.LinesIntersect(vertList[start].pos, vertList[start + 3].pos, vertList[start + 1].pos, vertList[start + 2].pos)
        if b {
            if linalg.length2(vertList[start + 3].pos - vertList[start].pos) < linalg.length2(vertList[start + 2].pos - vertList[start + 1].pos) {
                non_zero_append(indList, start, start + 1, start + 3, start, start + 3, start + 2)
            } else {
                non_zero_append(indList, start, start + 1, start + 2, start + 2, start + 1, start + 3)
            }
            return
        }
        if linalg.length2(vertList[start + 1].pos - vertList[start].pos) < linalg.length2(vertList[start + 3].pos - vertList[start + 2].pos) {
            non_zero_append(indList, start, start + 2, start + 1, start, start + 1, start + 3)
        } else {
            non_zero_append(indList, start, start + 2, start + 3, start + 3, start + 2, start + 1)
        }
    }
    appendLine(vertList, indList, color,pts_[:len(pts)], F)

    if len(pts) == 3 {
        non_zero_append(outPoly, CurveStruct{pts[0], false}, CurveStruct{pts[1], true})
    } else {
        non_zero_append(outPoly, CurveStruct{pts[0], false}, CurveStruct{pts[1], true}, CurveStruct{pts[2], true})
    }

    return .None
}

@(private="file") CurveStruct :: struct {
    p:linalg.PointF,
    isCurve:bool,
}

//TODO (xfitgd) Stroke
Shapes_ComputePolygon :: proc(poly:^Shapes, allocator := context.allocator) -> (res:^RawShape = nil, err:ShapesError = .None) {
    vertList:[dynamic]ShapeVertex2D = mem.make_non_zeroed_dynamic_array([dynamic]ShapeVertex2D, allocator)
    indList:[dynamic]u32 = mem.make_non_zeroed_dynamic_array([dynamic]u32, allocator)

    res = mem.new_non_zeroed(RawShape, allocator)

    defer if err != .None {
        delete(vertList)
        delete(indList)
        free(res, allocator)
        res = nil
    }

    Shapes_ComputePolygon_In :: proc(vertList:^[dynamic]ShapeVertex2D, indList:^[dynamic]u32, poly:^Shapes, allocator := context.allocator) -> (err:ShapesError = .None) {
        outPoly:[][dynamic]CurveStruct = mem.make_non_zeroed_slice([][dynamic]CurveStruct, len(poly.nPolys), context.temp_allocator)
        outPoly2:[dynamic]linalg.PointF = mem.make_non_zeroed_dynamic_array([dynamic]linalg.PointF, context.temp_allocator)
        outPoly2N:[]u32 = mem.make_non_zeroed_slice([]u32, len(poly.nPolys), context.temp_allocator)
        for &o in outPoly {
            o = mem.make_non_zeroed_dynamic_array([dynamic]CurveStruct, context.temp_allocator)
        }

        defer {
            for o in outPoly {
                delete(o)
            }
            delete(outPoly, context.temp_allocator)
            delete(outPoly2)
            delete(outPoly2N, context.temp_allocator)
        }

        start :u32 = 0
        typeIdx :u32 = 0

        for n,e in poly.nPolys {
            if poly.colors != nil && poly.colors[e].a > 0 {
                for i:u32 = start; i < start+n; typeIdx += 1 {
                    if poly.types[typeIdx] == .Line {
                        non_zero_append(&outPoly[e], CurveStruct{poly.poly[i], false})
                        i += 1
                    } else if poly.types[typeIdx] == .Quadratic {
                        pts := [3]linalg.PointF{poly.poly[i], poly.poly[i+1], i + 2 == start+n ? poly.poly[start] : poly.poly[i+2]}
                        err = _Shapes_ComputeLine(
                            vertList,
                            indList,
                            &outPoly[e],
                            poly.colors[e],
                            pts[:],
                            .Quadratic, 0.5)
                        if err != .None do return
                        i += 2
                    } else {
                        pts := [4]linalg.PointF{poly.poly[i], poly.poly[i+1], poly.poly[i+2], i + 3 == start+n ? poly.poly[start] : poly.poly[i+3]}
                        err = _Shapes_ComputeLine(
                            vertList,
                            indList,
                            &outPoly[e],
                            poly.colors[e],
                            pts[:],
                            .Unknown, 0.5)//TODO (xfitgd) 일단은 0.5로 고정
                        if err != .None do return
                        i += 3
                    }
                }
            } else {
                typeIdx += poly.nTypes[e]
            }
            start += n
        }

        for ps, psi in outPoly {
            if len(ps) == 0 do continue
            np :u32 = 0

            pT := mem.make_non_zeroed_dynamic_array([dynamic]linalg.PointF, context.temp_allocator )
            defer delete(pT)
            for p in ps {
                if !p.isCurve {
                    non_zero_append(&pT, p.p)
                }
            }

            if linalg.GetPolygonOrientation(pT[:]) == .Clockwise {
                for p in ps {
                    non_zero_append(&outPoly2, p.p)
                    np += 1
                }
            } else {
                for p,i in ps {
                    if p.isCurve {
                        if linalg.PointInPolygon(p.p, pT[:]) {
                            non_zero_append(&outPoly2, p.p)
                            np += 1
                        }
                    } else {
                        non_zero_append(&outPoly2, p.p)
                        np += 1
                    }
                }
            }

            outPoly2N[psi] = np
        }
        if len(outPoly2) == 0 do return

        indicesT, tErr := poly2tri.TrianguatePolygons(outPoly2[:], outPoly2N[:], context.temp_allocator)
        defer delete(indicesT, context.temp_allocator)
        
        if tErr != .None {
            err = auto_cast tErr
            return
        }
    
        start = 0
        vLen :u32 = auto_cast len(vertList)//Existing Curve Vertices Length
        for _, i in outPoly2N {
            for idx in start..<start+outPoly2N[i] {
                non_zero_append(vertList, ShapeVertex2D{
                    pos = outPoly2[idx],
                    uvw = {1,0,0},
                    color = poly.colors[i],
                })
            }
            start += outPoly2N[i]
        }
        //???! if len(indList) > 0 {
            for _, i in indicesT {
                indicesT[i] += vLen
            }
            non_zero_append(indList, ..indicesT)
        //!}
        return
    }


    err = Shapes_ComputePolygon_In(&vertList, &indList, poly, allocator)
    if err != .None do return

    //TODO (xfitgd)
    // if poly.thickness != nil && poly.strokeColors != nil {
    //     np :u32 = 0
    //     nt :u32 = 0
    //     for i in 0..<len(poly.thickness) {
    //         if poly.thickness[i] > 0.0 && poly.strokeColors[i].a > 0.0 {
    //             polyT:Shapes
    //             polyT.poly = mem.make_non_zeroed_slice([]linalg.PointF, poly.nPolys[i] * 2, context.temp_allocator)
    //             defer delete(polyT.poly, context.temp_allocator)

    //             ccw := linalg.GetPolygonOrientation(poly.poly[np:np + poly.nPolys[i]])
    //             if ccw == .CounterClockwise {
    //                 for j in 0..<int(poly.nPolys[i]) {
    //                     if j == 0 {
    //                         polyT.poly[poly.nPolys[i] + 0] = poly.poly[np + u32(j)]
    //                     } else {
    //                         polyT.poly[poly.nPolys[i] + (poly.nPolys[i] - u32(j))] = poly.poly[np + u32(j)]
    //                     }
    //                 }
    //                 pt1 := linalg.offsetPolygon(poly.poly[np:np + poly.nPolys[i]], poly.thickness[i], context.temp_allocator)
    //                 defer delete(pt1, context.temp_allocator)
    //                 pt2 := linalg.offsetPolygon(polyT.poly[poly.nPolys[i]:poly.nPolys[i] + poly.nPolys[i]], poly.thickness[i], context.temp_allocator)
    //                 defer delete(pt2, context.temp_allocator)

    //                 for &p, i in polyT.poly[0:poly.nPolys[i]] {
    //                     p = pt1[i]
    //                 }
    //                 for &p, i in polyT.poly[poly.nPolys[i]:poly.nPolys[i] + poly.nPolys[i]] {
    //                     p = pt2[i]
    //                 }
    //             } else {
    //                 for j in 0..<int(poly.nPolys[i]) {
    //                     if j == 0 {
    //                         polyT.poly[0] = poly.poly[np + u32(j)]
    //                     } else {
    //                         polyT.poly[poly.nPolys[i] - u32(j)] = poly.poly[np + u32(j)]
    //                     }
    //                 }
    //                 pt1 := linalg.offsetPolygon(polyT.poly[0:poly.nPolys[i]], -poly.thickness[i], context.temp_allocator)
    //                 defer delete(pt1, context.temp_allocator)
    //                 pt2 := linalg.offsetPolygon(poly.poly[np:np + poly.nPolys[i]], -poly.thickness[i], context.temp_allocator)
    //                 defer delete(pt2, context.temp_allocator)

    //                 for &p, i in polyT.poly[0:poly.nPolys[i]] {
    //                     p = pt1[i]
    //                 }
    //                 for &p, i in polyT.poly[poly.nPolys[i]:poly.nPolys[i] + poly.nPolys[i]] {
    //                     p = pt2[i]
    //                 }
    //             }


    //             polyT.colors = mem.make_non_zeroed_slice([]linalg.Point3DwF, 2, context.temp_allocator)
    //             defer delete( polyT.colors, context.temp_allocator)
    //             polyT.colors[0] = poly.strokeColors[i]
    //             polyT.colors[1] = poly.strokeColors[i]

    //             polyT.nPolys = mem.make_non_zeroed_slice([]u32, 2, context.temp_allocator)
    //             defer delete( polyT.nPolys, context.temp_allocator)
    //             polyT.nPolys[0] = poly.nPolys[i]
    //             polyT.nPolys[1] = poly.nPolys[i]

    //             polyT.nTypes = mem.make_non_zeroed_slice([]u32, 2, context.temp_allocator)
    //             defer delete( polyT.nTypes, context.temp_allocator)
    //             polyT.nTypes[0] = poly.nTypes[i]
    //             polyT.nTypes[1] = poly.nTypes[i]

    //             polyT.types = mem.make_non_zeroed_slice([]CurveType, poly.nTypes[i] * 2, context.temp_allocator)
    //             defer delete( polyT.types, context.temp_allocator)

    //             if ccw == .CounterClockwise {
    //                 mem.copy_non_overlapping(&polyT.types[0], &poly.types[nt], size_of(CurveType) * int(poly.nTypes[i]))
    //                 for j in int(poly.nTypes[i])..<int(poly.nTypes[i] * 2) {
    //                     polyT.types[j] = poly.types[nt + (poly.nTypes[i] * 2 - u32(j) - 1)]
    //                 }
    //             } else {
    //                 for j in 0..<int(poly.nTypes[i]) {
    //                     polyT.types[j] = poly.types[nt + (poly.nTypes[i] - u32(j) - 1)]
    //                 }
    //                 mem.copy_non_overlapping(&polyT.types[poly.nTypes[i]], &poly.types[nt], size_of(CurveType) * int(poly.nTypes[i]))
    //             }

    //             err = Shapes_ComputePolygon_In(&vertList, &indList, &polyT, allocator)
    //             if err != .None do return
    //         }
    //         np += poly.nPolys[i]
    //         nt += poly.nTypes[i]
    //     }
    // }

    shrink(&vertList)
    shrink(&indList)
    res.vertices = vertList[:]
    res.indices = indList[:]

    return
}

