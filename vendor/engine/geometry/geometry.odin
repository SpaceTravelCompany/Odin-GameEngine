package geometry

import "core:math"
import "core:slice"
import "core:fmt"
import "core:mem"
import "core:debug/trace"
import "core:math/linalg"
import "base:runtime"
import "base:intrinsics"


ShapeVertex2D :: struct #align(1) {
    pos: linalg.PointF,
    uvw: linalg.Point3DF,
    //color: linalg.Point3DwF,
};

RawShape :: struct {
    vertices : [][]ShapeVertex2D,
    indices:[][]u32,
    colors:[]linalg.Point3DwF,
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

    IsPointNotLine,
    IsNotCurve,
    InvaildLine,
    OutOfIdx,
    IsNotPolygon,
    invaildPolygonLineCounts,

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
    poly:[]linalg.PointF,//len(poly) == all sum nPolys
    nPolys:[]u32,
    types:[]CurveType,
    colors:[]Maybe(linalg.Point3DwF),//same length as nPolys
    strokeColors:[]Maybe(linalg.Point3DwF),//same length as nPolys
    thickness:[]f32,//same length as nPolys
}

CvtQuadraticToCubic0 :: #force_inline proc "contextless" (_start : linalg.PointF, _control : linalg.PointF) -> linalg.PointF {
    return linalg.PointF{ _start.x + (2.0/3.0) * (_control.x - _start.x), _start.y + (2.0/3.0) * (_control.y - _start.y) }
}
CvtQuadraticToCubic1 :: #force_inline proc "contextless" (_end : linalg.PointF, _control : linalg.PointF) -> linalg.PointF {
    return CvtQuadraticToCubic0(_end, _control)
}


RawShape_Free :: proc (self:^RawShape, allocator := context.allocator) {
    for i in 0..<len(self.vertices) {
        delete(self.vertices[i], allocator)
        delete(self.indices[i], allocator)
    }
    delete(self.vertices, allocator)
    delete(self.indices, allocator)
    delete(self.colors, allocator)
    free(self, allocator)
}

RawShape_Clone :: proc (self:^RawShape, allocator := context.allocator) -> (res:^RawShape = nil) {
    res = new(RawShape, allocator)
    res.vertices = mem.make_non_zeroed_slice([][]ShapeVertex2D, len(self.vertices), allocator)
    res.indices = mem.make_non_zeroed_slice([][]u32, len(self.indices), allocator)
    res.colors = mem.make_non_zeroed_slice([]linalg.Point3DwF, len(self.colors), allocator)
    for i in 0..<len(self.vertices) {
        res.vertices[i] = mem.make_non_zeroed_slice([]ShapeVertex2D, len(self.vertices[i]), allocator)
        res.indices[i] = mem.make_non_zeroed_slice([]u32, len(self.indices[i]), allocator)

        intrinsics.mem_copy_non_overlapping(&res.vertices[i][0], &self.vertices[i][0], len(self.vertices[i]) * size_of(ShapeVertex2D))
        intrinsics.mem_copy_non_overlapping(&res.indices[i][0], &self.indices[i][0], len(self.indices[i]) * size_of(u32)) 
    }
    intrinsics.mem_copy_non_overlapping(&res.colors[0], &self.colors[0], len(self.colors) * size_of(linalg.Point3DwF))
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
    pts:[]linalg.PointF,
    baseIdx :u32,
    _repeat :int = -1) -> ShapesError {
    err:ShapesError = .None
    outD:[3]f32 = {0, 0, 0}
    curveType :CurveType

    if len(pts) == 3 {
        curveType = .Quadratic
    } else if len(pts) == 4 {
        err : ShapesError

        curveType, err, outD = GetCubicCurveType(pts[0], pts[1], pts[2], pts[3])
        if err != .None do return err
    } else if len(pts) == 2 {
        return .None//Line
    } else {
        trace.panic_log("Shapes_ComputeLine: unknown curve type")
    }
    
    pts_:[4]linalg.PointF
    intrinsics.mem_copy_non_overlapping(&pts_[0], &pts[0], len(pts) * size_of(linalg.PointF))

    reverse := false
    subdiv :f32 = 0.0

    F :[4][3]f32

    reverseOrientation :: #force_inline proc "contextless" (F:^[4][3]f32) {
        F[0][0] *= -1
        F[0][1] *= -1
        F[1][0] *= -1
        F[1][1] *= -1
        F[2][0] *= -1
        F[2][1] *= -1
        F[3][0] *= -1
        F[3][1] *= -1
    }
    artifact := 0

    switch curveType {
        case .Line:
            return .None
        case .Quadratic:
            F = {
                {0,              0,              0},         
                {-1.0/3.0,        0,              1.0/3.0},    
                {-2.0/3.0,        -1.0/3.0,        2.0/3.0},   
                {-1,              -1,              1},      
            }
            //if outD[2] < 0 do reverse = true
        case .Serpentine:
            t1 := math.sqrt_f32(9.0 * outD[1] * outD[1] - 12 * outD[0] * outD[2])
            ls := 3.0 * outD[1] - t1
            lt := 6.0 * outD[0]
            ms := 3.0 * outD[1] + t1
            mt := lt
            ltMinusLs := lt - ls
            mtMinusMs := mt - ms

            F = {
                {ls * ms,                                                            ls * ls * ls,                           ms * ms * ms},
                {(1.0 / 3.0) * (3.0 * ls * ms - ls * mt - lt * ms),                  ls * ls * (ls - lt),                    ms * ms * (ms - mt)},
                {(1.0 / 3.0) * (lt * (mt - 2.0 * ms) + ls * (3.0 * ms - 2.0 * mt)),  ltMinusLs * ltMinusLs * ls,             mtMinusMs * mtMinusMs * ms},
                {ltMinusLs * mtMinusMs,                                              -(ltMinusLs * ltMinusLs * ltMinusLs),   -(mtMinusMs * mtMinusMs * mtMinusMs)},
            }

            if F[0][0] > 0.0 do reverse = true
        case .Loop:
            t1 := math.sqrt_f32(4 * outD[0] * outD[2] - 3 * outD[1] * outD[1])
            ls := outD[1] - t1
            lt := 2 * outD[0]
            ms := outD[1] + t1
            mt := lt

            ql := ls / lt
            qm := ms / mt
            
            if _repeat == -1 && 0.0 < ql && ql < 1.0 {
                artifact = 1
                subdiv = ql
            } else if _repeat == -1 && 0.0 < qm && qm < 1.0 {
                artifact = 2
                subdiv = qm
            } else {
                ltMinusLs := lt - ls
                mtMinusMs := mt - ms

                F = {
                    {ls * ms,                                                            ls * ls * ms,                           ls * ms * ms},

                    {(1.0/3.0) * (-ls * mt - lt * ms + 3.0 * ls * ms),
                    -(1.0 / 3.0) * ls * (ls * (mt - 3.0 * ms) + 2.0 * lt * ms),
                    -(1.0 / 3.0) * ms * (ls * (2.0 * mt - 3.0 * ms) + lt * ms)},

                    {(1.0/3.0) * (lt * (mt - 2.0 * ms) + ls * (3.0 * ms - 2.0 * mt)),
                    (1.0/3.0) * ltMinusLs * (ls * (2.0 * mt - 3.0 * ms) + lt * ms),
                    (1.0/3.0) * mtMinusMs * (ls * (mt - 3.0 * ms) + 2.0 * lt * ms)},
                    
                    {ltMinusLs * mtMinusMs,  -(ltMinusLs * ltMinusLs) * mtMinusMs,   -ltMinusLs * mtMinusMs * mtMinusMs},
                }
        
                reverse = F[1][0] > 0.0
            }
        case .Cusp:
            ls := outD[2]
            lt := 3.0 * outD[1]
            lsMinusLt := ls - lt
            F = {
                {ls,                         ls * ls * ls,                       1},
                {(ls - (1.0 / 3.0) * lt),    ls * ls * lsMinusLt,                1},
                {ls - (2.0 / 3.0) * lt,      lsMinusLt * lsMinusLt * ls,         1},
                {lsMinusLt,                  lsMinusLt * lsMinusLt * lsMinusLt,  1},
            }
            reverse = true
        case .Unknown:
            trace.panic_log("GetCubicCurveType: unknown curve type")
    }
   

    if artifact != 0 {
        //!X no need Quadratic
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

        non_zero_append(indList, u32(len(vertList)) + baseIdx, u32(len(vertList) + 1) + baseIdx, u32(len(vertList) + 2) + baseIdx)
        non_zero_append(vertList, ShapeVertex2D{pos = pts[0], uvw = {1.0, 0.0, 0.0}})
        non_zero_append(vertList, ShapeVertex2D{pos = { x123, y123 }, uvw = {1.0, 0.0, 0.0}})
        non_zero_append(vertList, ShapeVertex2D{pos = pts[3], uvw = {1.0, 0.0, 0.0}})

        err := _Shapes_ComputeLine(vertList, indList, {pts[0], { x01, y01 }, { x012, y012 }, { x0123, y0123 }}, baseIdx, artifact == 1 ? 0 : 1)
        if err != .None do return err
        err = _Shapes_ComputeLine(vertList, indList, {{ x0123, y0123 }, { x123, y123 }, { x23, y23 }, pts[3]}, baseIdx, artifact == 1 ? 1 : 0)
        if err != .None do return err
        return .None
    }
    // if _repeat == 1 {
    //     reverse = !reverse
    // }

    if reverse {
        reverseOrientation(&F)
    }

    appendLine :: proc (vertList:^[dynamic]ShapeVertex2D, indList:^[dynamic]u32, pts:[]linalg.PointF, F:^[4][3]f32, baseIdx:u32) {
        if len(pts) == 2 {
            return
        }
        start :u32 = u32(len(vertList))
        non_zero_append(vertList, ShapeVertex2D{
            uvw = {F[0][0], F[0][1], F[0][2]},
        })
        non_zero_append(vertList, ShapeVertex2D{
            uvw = {F[1][0], F[1][1], F[1][2]},
        })
        non_zero_append(vertList, ShapeVertex2D{
            uvw = {F[2][0], F[2][1], F[2][2]},
        })
        non_zero_append(vertList, ShapeVertex2D{
            uvw = {F[3][0], F[3][1], F[3][2]},
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
                    indices :[3]u32 = {start + baseIdx, start + baseIdx, start + baseIdx}
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
                    non_zero_append(indList, indices[k] + baseIdx)
                    non_zero_append(indList, indices[(k + 1)%3] + baseIdx)
                    non_zero_append(indList, start + i + baseIdx)
                }
                return
            }
        }

        b := linalg.LinesIntersect(vertList[start].pos, vertList[start + 2].pos, vertList[start + 1].pos, vertList[start + 3].pos)
        if b {
            if linalg.length2(vertList[start + 2].pos - vertList[start].pos) < linalg.length2(vertList[start + 3].pos - vertList[start + 1].pos) {
                non_zero_append(indList, start + baseIdx, start + 1 + baseIdx, start + 2 + baseIdx, start + baseIdx, start + 2 + baseIdx, start + 3 + baseIdx)
            } else {
                non_zero_append(indList, start + baseIdx, start + 1 + baseIdx, start + 3 + baseIdx, start + 1 + baseIdx, start + 2 + baseIdx, start + 3 + baseIdx)
            }
            return
        }
        b = linalg.LinesIntersect(vertList[start].pos, vertList[start + 3].pos, vertList[start + 1].pos, vertList[start + 2].pos)
        if b {
            if linalg.length2(vertList[start + 3].pos - vertList[start].pos) < linalg.length2(vertList[start + 2].pos - vertList[start + 1].pos) {
                non_zero_append(indList, start + baseIdx, start + 1 + baseIdx, start + 3 + baseIdx, start + baseIdx, start + 3 + baseIdx, start + 2 + baseIdx)
            } else {
                non_zero_append(indList, start + baseIdx, start + 1 + baseIdx, start + 2 + baseIdx, start + 2 + baseIdx, start + 1 + baseIdx, start + 3 + baseIdx)
            }
            return
        }
        if linalg.length2(vertList[start + 1].pos - vertList[start].pos) < linalg.length2(vertList[start + 3].pos - vertList[start + 2].pos) {
            non_zero_append(indList, start + baseIdx, start + 2 + baseIdx, start + 1 + baseIdx, start + baseIdx, start + 1 + baseIdx, start + 3 + baseIdx)
        } else {
            non_zero_append(indList, start + baseIdx, start + 2 + baseIdx, start + 3 + baseIdx, start + 3 + baseIdx, start + 2 + baseIdx, start + 1 + baseIdx)
        }
    }
    appendLine(vertList, indList, pts_[:len(pts)], &F, baseIdx)

    return .None
}

@(private="file") CurveStruct :: struct {
    p:linalg.PointF,
    isCurve:bool,
}

Shapes_ComputePolygon :: proc(poly:^Shapes, allocator := context.allocator) -> (res:^RawShape = nil, err:ShapesError = .None) {
    vertList:[dynamic][]ShapeVertex2D = mem.make_non_zeroed_dynamic_array([dynamic][]ShapeVertex2D, allocator)
    indList:[dynamic][]u32 = mem.make_non_zeroed_dynamic_array([dynamic][]u32, allocator)
    colList:[dynamic]linalg.Point3DwF = mem.make_non_zeroed_dynamic_array([dynamic]linalg.Point3DwF, allocator)

    res = mem.new_non_zeroed(RawShape, allocator)

    defer if err != .None {
        delete(vertList)
        delete(indList)
        delete(colList)
        free(res, allocator)
        res = nil
    }

    idx :u32 = 0
    typeIdx :u32 = 0
    for i in 0..<len(poly.nPolys) {
        if poly.colors[i] != nil {
            vertSubList:[dynamic]ShapeVertex2D = mem.make_non_zeroed_dynamic_array([dynamic]ShapeVertex2D, allocator)
            indSubList:[dynamic]u32 = mem.make_non_zeroed_dynamic_array([dynamic]u32, allocator)

            err, idx, typeIdx = Shapes_ComputePolygon_In(&vertSubList, &indSubList, poly, i, idx, typeIdx, allocator)
            if err != .None {
                for v in vertList {
                    delete(v, allocator)
                }
                for i in indList {
                    delete(i, allocator)
                }
                delete(vertSubList)
                delete(indSubList)
                return
            }
            polyPrevColor :: proc "contextless" (poly:^Shapes, i:int) -> (Maybe(linalg.Point3DwF), int) {
                if i == 0 {
                    return nil, 0
                } else {
                    j := i - 1
                    for j != -1 && poly.colors[j] == nil {
                        j -= 1
                    }
                    if j == -1 do return nil, 0
                    return poly.colors[j].?, j
                }
            }
            prevColor, prevColorIdx := polyPrevColor(poly, i)
            if prevColor == nil || poly.colors[prevColorIdx].? != poly.colors[i].? {
                shrink(&vertSubList)
                shrink(&indSubList)
                non_zero_append(&vertList, vertSubList[:])
                non_zero_append(&indList, indSubList[:])
                non_zero_append(&colList, poly.colors[i].?)
            } else {
                newVerts := mem.make_non_zeroed([]ShapeVertex2D, len(vertList[len(vertList) - 1]) + len(vertSubList), allocator)
                newIns := mem.make_non_zeroed([]u32, len(indList[len(indList) - 1]) + len(indSubList), allocator)

                runtime.mem_copy_non_overlapping(&newVerts[0], &vertList[len(vertList) - 1][0], len(vertList[len(vertList) - 1]) * size_of(ShapeVertex2D))
                runtime.mem_copy_non_overlapping(&newVerts[len(vertList[len(vertList) - 1])], &vertSubList[0], len(vertSubList) * size_of(ShapeVertex2D))
                runtime.mem_copy_non_overlapping(&newIns[0], &indList[len(indList) - 1][0], len(indList[len(indList) - 1]) * size_of(u32))
                runtime.mem_copy_non_overlapping(&newIns[len(indList[len(indList) - 1])], &indSubList[0], len(indSubList) * size_of(u32))

                delete(vertSubList)
                delete(indSubList)
                delete(vertList[len(vertList) - 1], allocator)
                delete(indList[len(indList) - 1], allocator)

                resize(&vertList, len(vertList) - 1)
                resize(&indList, len(indList) - 1)
                non_zero_append(&vertList, newVerts)
                non_zero_append(&indList, newIns)
            }
        }
        // if poly.strokeColors != nil && poly.strokeColors[i] != nil && poly.thickness[i] > 0.0 {
        //     //TODO (xfitgd) Shapes_ComputePolygon_Stroke_In
        //     non_zero_append(&colList, poly.strokeColors[i].?)
        // }
    }

    Shapes_ComputePolygon_In :: proc(vertSubList:^[dynamic]ShapeVertex2D, indSubList:^[dynamic]u32, poly:^Shapes, startPoly:int, startIdx:u32, startTypeIdx:u32, allocator := context.allocator) ->
    (err:ShapesError = .None, idx:u32, typeIdx:u32) {
        count :u32= 0
        typeIdx = startTypeIdx

        typeLen :u32= typeIdx
        typeLen2 :u32= typeIdx
        idx = startIdx
        start_ :u32= 0
        n := poly.nPolys[startPoly]
        for e in 0..<startPoly {
            start_ += u32(poly.nPolys[e])
        }
        i :u32= start_
        typeFirstIdx :u32 = 0

        non_zero_append(vertSubList, ShapeVertex2D{pos = linalg.PointF{math.F32_MAX, -math.F32_MAX}, uvw = linalg.Point3DF{1.0, 0.0, 0.0},})

        maxX :f32 = -math.F32_MAX
        minY :f32 = math.F32_MAX
        
        for typeFirstIdx < n {
            t := poly.types[typeLen]

            non_zero_append(vertSubList, ShapeVertex2D{pos =poly.poly[i], uvw = linalg.Point3DF{1.0, 0.0, 0.0},})
            last_vert := &vertSubList[len(vertSubList) - 1]
            if vertSubList[0].pos.x > last_vert.pos.x do vertSubList[0].pos.x = last_vert.pos.x
            if vertSubList[0].pos.y < last_vert.pos.y do vertSubList[0].pos.y = last_vert.pos.y

            if maxX < last_vert.pos.x do maxX = last_vert.pos.x
            if minY > last_vert.pos.y do minY = last_vert.pos.y

            non_zero_append(indSubList, idx)
            non_zero_append(indSubList, u32(len(vertSubList) - 1) + idx)
            
            if t == .Quadratic {
                if typeFirstIdx + 1 >= n - 1 {
                    i += 1
                } else {
                    i += 2
                }
                typeFirstIdx += 2              
            } else if t == .Line {
                if typeFirstIdx >= n - 1 {
                } else {
                    i += 1
                }
                typeFirstIdx += 1
            } else {
                if typeFirstIdx + 2 >= n - 1 {
                    i += 2
                } else {
                    i += 3
                }
                typeFirstIdx += 3
            }
            typeLen += 1

            non_zero_append(indSubList, typeFirstIdx < n ? u32(len(vertSubList) - 1 + 1) + idx : idx + 1)  
        }

        vertSubList[0].pos.x -= ((maxX - vertSubList[0].pos.x) / 2.0)
        vertSubList[0].pos.y += ((vertSubList[0].pos.y - minY) / 2.0)

        i = start_
        typeFirstIdx = 0
        for typeFirstIdx < n {
            t := poly.types[typeLen2]
            l :[]linalg.PointF
            ll:[]linalg.PointF = nil

            if t == .Quadratic {
                if typeFirstIdx + 1 >= n - 1 {
                    ll = make([]linalg.PointF, 3, context.temp_allocator)
                    ll[0] = poly.poly[i]
                    ll[1] = poly.poly[i + 1]
                    ll[2] = poly.poly[start_]
                    l = ll
                    i += 1
                } else {
                    l = poly.poly[i:i + 3]
                    i += 2
                }
                typeFirstIdx += 2              
            } else if t == .Line {
                if typeFirstIdx >= n - 1 {
                    ll = make([]linalg.PointF, 2, context.temp_allocator)
                    ll[0] = poly.poly[i]
                    ll[1] = poly.poly[start_]
                    l = ll
                } else {
                    l = poly.poly[i:i + 2]
                    i += 1
                }
                typeFirstIdx += 1
            } else {
                if typeFirstIdx + 2 >= n - 1 {
                    ll = make([]linalg.PointF, 4, context.temp_allocator)
                    ll[0] = poly.poly[i]
                    ll[1] = poly.poly[i + 1]
                    ll[2] = poly.poly[i + 2]
                    ll[3] = poly.poly[start_]
                    l = ll
                    i += 2
                } else {
                    l = poly.poly[i:i + 4]
                    i += 3
                }
                typeFirstIdx += 3
            }
            defer if ll != nil do delete(ll, context.temp_allocator)

            err = _Shapes_ComputeLine(vertSubList, indSubList, l, idx, -1)
            if err != .None do return

            typeLen2 += 1
        }
        idx += u32(len(vertSubList))
        typeIdx = typeLen2
        return
    }

    res.vertices = vertList[:]
    res.indices = indList[:]
    res.colors = colList[:]
    return
}

