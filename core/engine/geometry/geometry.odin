package geometry

import "base:intrinsics"
import "base:runtime"
import "core:debug/trace"
import "core:math"
import "core:math/linalg"
import "core:math/poly2tri"
import "core:mem"


// 스트로크 스타일 정의
stroke_cap :: enum {
    Butt,    // 평평한 끝
    Round,   // 둥근 끝
    Square,  // 사각형 끝
}

stroke_join :: enum {
    Miter,   // 뾰족한 연결
    Round,   // 둥근 연결
    Bevel,   // 베벨 연결
}

stroke_style :: struct {
    width: f32,
    cap: stroke_cap,
    join: stroke_join,
    miter_limit: f32,  // Miter join에서 사용
}

shape_vertex2d :: struct #align(1) {
    pos: linalg.PointF,
    uvw: linalg.Point3DF,
    color: linalg.Point3DwF,
};

raw_shape :: struct {
    vertices : []shape_vertex2d,
    indices:[]u32,
    rect:linalg.RectF,
}

curve_type :: enum {
    Line,
    Unknown,
    Serpentine,
    Loop,
    Cusp,
    Quadratic,
}

@private __ShapesError :: enum {
    //!None, no need

    IsPointNotLine,
    IsNotCurve,
    InvaildLine,
    OutOfIdx,
    IsNotPolygon,
    invaildPolygonLineCounts,
    CantPolygonMatchHoles,

    EmptyPolygon,
    EmptyColor,
}

shape_error :: union #shared_nil {
    __ShapesError,
    poly2tri.Trianguate_Error,
}

shapes :: struct {
    poly:[]linalg.PointF,//len(poly) == all sum n_polys
    n_polys:[]u32,
    n_types:[]u32,
    types:[]curve_type,
    colors:[]linalg.Point3DwF,//same length as n_polys
    strokeColors:[]linalg.Point3DwF,//same length as n_polys
    thickness:[]f32,//same length as n_polys
}

CvtQuadraticToCubic0 :: #force_inline proc "contextless" (_start : linalg.PointF, _control : linalg.PointF) -> linalg.PointF {
    return linalg.PointF{ _start.x + (2.0/3.0) * (_control.x - _start.x), _start.y + (2.0/3.0) * (_control.y - _start.y) }
}
CvtQuadraticToCubic1 :: #force_inline proc "contextless" (_end : linalg.PointF, _control : linalg.PointF) -> linalg.PointF {
    return CvtQuadraticToCubic0(_end, _control)
}

/*
Frees a raw shape and its resources

Inputs:
- self: Pointer to the raw shape to free
- allocator: Allocator used for the shape (default: context.allocator)

Returns:
- None
*/
raw_shape_free :: proc (self:^raw_shape, allocator := context.allocator) {
    if self == nil do return
    delete(self.vertices, allocator)
    delete(self.indices, allocator)
    free(self, allocator)
}

/*
Clones a raw shape

Inputs:
- self: Pointer to the raw shape to clone
- allocator: Allocator to use for the clone (default: context.allocator)

Returns:
- Pointer to the cloned raw shape
*/
raw_shape_clone :: proc (self:^raw_shape, allocator := context.allocator) -> (res:^raw_shape = nil) {
    res = new(raw_shape, allocator)
    res.vertices = mem.make_non_zeroed_slice([]shape_vertex2d, len(self.vertices), allocator)
    res.indices = mem.make_non_zeroed_slice([]u32, len(self.indices), allocator)
    intrinsics.mem_copy_non_overlapping(&res.vertices[0], &self.vertices[0], len(self.vertices) * size_of(shape_vertex2d))
    intrinsics.mem_copy_non_overlapping(&res.indices[0], &self.indices[0], len(self.indices) * size_of(u32))

    res.rect = self.rect
    return
}



GetCubicCurveType :: proc "contextless" (_start:[2]$T, _control0:[2]T, _control1:[2]T, _end:[2]T) ->
(type:curve_type = .Unknown, err:shape_error = nil, outD:[3]T) where intrinsics.type_is_float(T) {

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
    vertList:^[dynamic]shape_vertex2d,
    indList:^[dynamic]u32,
    outPoly:^[dynamic]CurveStruct,
    color:linalg.Point3DwF,
    pts:[]linalg.PointF,
    type:curve_type,
    _subdiv :f32 = 0.0,
    _repeat :int = -1) -> shape_error {

    if _subdiv < 0 do trace.panic_log("_subdiv can't negative.")

    curveType := type
    err:shape_error = nil

    pts2 : [4][2]f32
    pts_:[4][2]f32
    intrinsics.mem_copy_non_overlapping(&pts_[0], &pts[0], len(pts) * size_of(linalg.PointF))

    reverse := false
    outD:[3]f32 = {0, 0, 0}
    if curveType != .Line && curveType != .Quadratic {
        curveType, err, outD = GetCubicCurveType(pts[0], pts[1], pts[2], pts[3])
        if err != nil do return err
    } else if curveType == .Quadratic {
        if _subdiv == 0.0 {
            vlen :u32 = u32(len(vertList))
            if linalg.GetPolygonOrientation(pts) == .CounterClockwise {
                non_zero_append(vertList, shape_vertex2d{
                    uvw = {0,0,0},
                    pos = pts[0],
                    color = color,
                })
                non_zero_append(vertList, shape_vertex2d{
                    uvw = {-0.5,0,0.5},
                    pos = pts[1],
                    color = color,
                })
                non_zero_append(vertList, shape_vertex2d{
                    uvw = {-1,-1,1},
                    pos = pts[2],
                    color = color,
                })
            } else {
                non_zero_append(vertList, shape_vertex2d{
                    uvw = {0,0,0},
                    pos = pts[0],
                    color = color,
                })
                non_zero_append(vertList, shape_vertex2d{
                    uvw = {0.5,0,0.5},
                    pos = pts[1],
                    color = color,
                })
                non_zero_append(vertList, shape_vertex2d{
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
            if err != nil do return err
            err = _Shapes_ComputeLine(vertList, indList, outPoly, color,{{ x012, y012 }, { x12, y12 }, pts[2]}, .Quadratic,0.0, 0)
            if err != nil do return err
        }
        return nil
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
                return nil
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
                        ls * ms,
                        ls * ls * ms,
                        ls * ms * ms, 0,
                        (1.0/3.0) * (-ls * mt - lt * ms + 3.0 * ls * ms),
                        -(1.0 / 3.0) * ls * (ls * (mt - 3.0 * ms) + 2.0 * lt * ms),
                        -(1.0 / 3.0) * ms * (ls * (2.0 * mt - 3.0 * ms) + lt * ms), 0,
                        (1.0/3.0) * (lt * (mt - 2.0 * ms) + ls * (3.0 * ms - 2.0 * mt)),
                        (1.0/3.0) * ltMinusLs * (ls * (2.0 * mt - 3.0 * ms) + lt * ms),
                        (1.0/3.0) * mtMinusMs * (ls * (mt - 3.0 * ms) + 2.0 * lt * ms), 0,
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

        //TODO (xfitgd) 일단은 무조건 곡선을 분할하는 코드를 작성함. 추후에는 필요한 부분만 분할하는 코드로 수정하는 최적화 필요
        if repeat == 2 {
            err := _Shapes_ComputeLine(vertList, indList, outPoly, color,{pts[0], { x01, y01 }, { x012, y012 }, { x0123, y0123 }}, type, 0.0, 1)
            if err != nil do return err
            err = _Shapes_ComputeLine(vertList, indList, outPoly, color,{{ x0123, y0123 }, { x123, y123 }, { x23, y23 }, pts[3]}, type, 0.0, 0)
            if err != nil do return err
        } else if repeat == 1 {
            err := _Shapes_ComputeLine(vertList, indList, outPoly, color,{pts[0], { x01, y01 }, { x012, y012 }, { x0123, y0123 }}, type, 0.0, 0)
            if err != nil do return err
            err = _Shapes_ComputeLine(vertList, indList, outPoly, color,{{ x0123, y0123 }, { x123, y123 }, { x23, y23 }, pts[3]}, type, 0.0, 1)
            if err != nil do return err
        } else {
            if _repeat == 3 {
                err := _Shapes_ComputeLine(vertList, indList, outPoly, color,{pts[0], { x01, y01 }, { x012, y012 }, { x0123, y0123 }}, type, 0.0, 0)
                if err != nil do return err
                err = _Shapes_ComputeLine(vertList, indList, outPoly, color,{{ x0123, y0123 }, { x123, y123 }, { x23, y23 }, pts[3]}, type, 0.0, 0)
                if err != nil do return err
            } else {
                err := _Shapes_ComputeLine(vertList, indList, outPoly, color,{pts[0], { x01, y01 }, { x012, y012 }, { x0123, y0123 }}, type, 0.5, 3)
                if err != nil do return err
                err = _Shapes_ComputeLine(vertList, indList, outPoly, color,{{ x0123, y0123 }, { x123, y123 }, { x23, y23 }, pts[3]}, type, 0.5, 3)
                if err != nil do return err
            }
        }
        return nil
    }
    if repeat == 1 {
        reverse = !reverse
    }

    if reverse {
      F = reverseOrientation(F)
    }

    appendLine :: proc (vertList:^[dynamic]shape_vertex2d, indList:^[dynamic]u32, color:linalg.Point3DwF, pts:[]linalg.PointF, F:matrix[4,4]f32) {
        if len(pts) == 2 {
            return
        }
        start :u32 = u32(len(vertList))
        non_zero_append(vertList, shape_vertex2d{
            uvw = {F[0,0], F[0,1], F[0,2]},
            color = color,
        })
        non_zero_append(vertList, shape_vertex2d{
            uvw = {F[1,0], F[1,1], F[1,2]},
            color = color,
        })
        non_zero_append(vertList, shape_vertex2d{
            uvw = {F[2,0], F[2,1], F[2,2]},
            color = color,
        })
        non_zero_append(vertList, shape_vertex2d{
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

    return nil
}

@(private="file") CurveStruct :: struct {
    p:linalg.PointF,
    isCurve:bool,
}

/*
Computes a polygon from shapes data

Inputs:
- poly: Pointer to the shapes data
- allocator: Allocator to use

Returns:
- Pointer to the computed raw shape
- An error if computation failed
*/
shapes_compute_polygon :: proc(poly:^shapes, allocator := context.allocator) -> (res:^raw_shape = nil, err:shape_error = nil) {
    vertList:[dynamic]shape_vertex2d = mem.make_non_zeroed_dynamic_array([dynamic]shape_vertex2d, context.temp_allocator)
    indList:[dynamic]u32 = mem.make_non_zeroed_dynamic_array([dynamic]u32, context.temp_allocator)

    res = mem.new_non_zeroed(raw_shape, allocator)

    defer {
        delete(vertList)
        delete(indList)
    }
    defer if err != nil {
        free(res, allocator)
        res = nil
    }

    shapes_compute_polygon_in :: proc(vertList:^[dynamic]shape_vertex2d, indList:^[dynamic]u32, poly:^shapes, allocator : runtime.Allocator) -> (err:shape_error = nil) {
        outPoly:[][dynamic]CurveStruct = mem.make_non_zeroed_slice([][dynamic]CurveStruct, len(poly.n_polys), context.temp_allocator)
        outPoly2:[dynamic]linalg.PointF = mem.make_non_zeroed_dynamic_array([dynamic]linalg.PointF, context.temp_allocator)
        outPoly2N:[]u32 = mem.make_non_zeroed_slice([]u32, len(poly.n_polys), context.temp_allocator)
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

        for n,e in poly.n_polys {
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
                        if err != nil do return
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
                        if err != nil do return
                        i += 3
                    }
                }
            } else {
                typeIdx += poly.n_types[e]
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
        
        if tErr != poly2tri.Trianguate_Error.None {
            err = tErr
            return
        }
    
        start = 0
        vLen :u32 = auto_cast len(vertList)//Existing Curve Vertices Length
        for _, i in outPoly2N {
            for idx in start..<start+outPoly2N[i] {
                non_zero_append(vertList, shape_vertex2d{
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


    if poly.colors != nil {
        err = shapes_compute_polygon_in(&vertList, &indList, poly, allocator)
        if err != nil do return
    }

    if poly.thickness != nil && poly.strokeColors != nil {
        polyT:^shapes = mem.new(shapes, context.temp_allocator)
        defer free(polyT, context.temp_allocator)

        polyT.poly = mem.make_non_zeroed_slice([]linalg.PointF, len(poly.poly) * 2, context.temp_allocator)
        defer delete(polyT.poly, context.temp_allocator)

        polyT.n_polys = mem.make_non_zeroed_slice([]u32, len(poly.n_polys) * 2, context.temp_allocator)
        defer delete(polyT.n_polys, context.temp_allocator)

        polyT.colors = mem.make_non_zeroed_slice([]linalg.Point3DwF, len(poly.strokeColors) * 2, context.temp_allocator)
        defer delete(polyT.colors, context.temp_allocator)

        polyT.types = mem.make_non_zeroed_slice([]curve_type, len(poly.types) * 2, context.temp_allocator)
        defer delete(polyT.types, context.temp_allocator)

        polyT.n_types = mem.make_non_zeroed_slice([]u32, len(poly.n_types) * 2, context.temp_allocator)
        defer delete(polyT.n_types, context.temp_allocator)

        start_ :u32 = 0
        start_2 :u32 = 0
        start_type :u32 = 0
        start_type2 :u32 = 0
        polyOri:linalg.PolyOrientation
        for i in 0..<len(poly.n_polys) {
            polyT.n_polys[i * 2] = poly.n_polys[i]
            polyT.n_polys[i * 2 + 1] = poly.n_polys[i]
            polyT.colors[i * 2] = poly.strokeColors[i]
            polyT.colors[i * 2 + 1] = poly.strokeColors[i]
            
            polyT.n_types[i * 2] = poly.n_types[i]
            polyT.n_types[i * 2 + 1] = poly.n_types[i]

            polyOri = linalg.GetPolygonOrientation(poly.poly[start_:start_ + poly.n_polys[i]])
            for e in 0..<poly.n_polys[i] {
                prevPoint := e == 0                  ? poly.poly[start_ + poly.n_polys[i] - 1] : poly.poly[start_ + e - 1]
                nextPoint := e == poly.n_polys[i] - 1 ? poly.poly[start_]                      : poly.poly[start_ + e + 1]

                polyT.poly[start_2 + e] = linalg.LineExtendPoint(prevPoint, poly.poly[start_ + e], nextPoint, poly.thickness[i], polyOri)
            }
            ReversePolygonExceptFirst :: proc "contextless" (poly: []linalg.PointF, types:[]curve_type) {
                count := len(poly) - 1
                for j in 0..<(count/2) {
                    tmp := poly[j + 1]
                    poly[j + 1] = poly[((count + 1) - j - 1)]
                    poly[((count + 1) - j - 1)] = tmp
                }

                count = len(types)
                for j in 0..<count/2 {
                    tmp := types[j]
                    types[j] = types[(count - j - 1)]
                    types[(count - j - 1)] = tmp
                }
            }
            for e in 0..<poly.n_types[i] {
                polyT.types[start_type2 + e] = poly.types[start_type + e]
            }
            if polyOri == .Clockwise do ReversePolygonExceptFirst(polyT.poly[start_2 : start_2 + poly.n_polys[i]], polyT.types[start_type2 : start_type2 + poly.n_types[i]])
            start_2 += poly.n_polys[i]
            start_type2 += poly.n_types[i]

            for e in 0..<poly.n_polys[i] {
                prevPoint := e == 0                  ? poly.poly[start_ + poly.n_polys[i] - 1] : poly.poly[start_ + e - 1]
                nextPoint := e == poly.n_polys[i] - 1 ? poly.poly[start_]                      : poly.poly[start_ + e + 1]

                polyT.poly[start_2 + e] = linalg.LineExtendPoint(prevPoint, poly.poly[start_ + e], nextPoint, -poly.thickness[i], polyOri)
            }
            for e in 0..<poly.n_types[i] {
                polyT.types[start_type2 + e] = poly.types[start_type + e]
            }
            if polyOri == .CounterClockwise do ReversePolygonExceptFirst(polyT.poly[start_2 : start_2 + poly.n_polys[i]], polyT.types[start_type2 : start_type2 + poly.n_types[i]])
            start_ += poly.n_polys[i]
            start_2 += poly.n_polys[i]
            start_type += poly.n_types[i]
            start_type2 += poly.n_types[i]
        }

        err = shapes_compute_polygon_in(&vertList, &indList, polyT, allocator)
        if err != nil do return
    }

    res.vertices = mem.make_non_zeroed_slice([]shape_vertex2d, len(vertList), allocator)
    res.indices = mem.make_non_zeroed_slice([]u32, len(indList), allocator)

    intrinsics.mem_copy_non_overlapping(&res.vertices[0], &vertList[0], len(vertList) * size_of(shape_vertex2d))
    intrinsics.mem_copy_non_overlapping(&res.indices[0], &indList[0], len(indList) * size_of(u32))

    return
}

