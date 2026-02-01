package geometry

import "base:intrinsics"
import "base:runtime"
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
    pos: linalg.point,
    uvw: linalg.point3d,
    color: linalg.point3dw,
    edge_boundary: [4]u8, // [0]=edge0, [1]=edge1, [2]=edge2 (1=AA/boundary), [3]=check_curve_or_not (0=curve, 1=line, 2=quadratic)
};

raw_shape :: struct {
    vertices : []shape_vertex2d,
    indices:[]u32,
    rect:linalg.rect,
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
    mem.Allocator_Error,
}

shape_line :: struct {
    start: linalg.point,
    control0: linalg.point,
    control1: linalg.point,
    end: linalg.point,
    /// default value 'Unknown' recongnises curve type 'cubic'
    type: curve_type,
}

shape_node :: struct {
    lines: []shape_line,
    color: linalg.point3dw,
    stroke_color: linalg.point3dw,
    thickness: f32,
}

shapes :: struct {
    nodes: []shape_node,
}

CvtQuadraticToCubic0 :: #force_inline proc "contextless" (_start : linalg.point, _control : linalg.point) -> linalg.point {
    return linalg.point{ _start.x + (2.0/3.0) * (_control.x - _start.x), _start.y + (2.0/3.0) * (_control.y - _start.y) }
}
CvtQuadraticToCubic1 :: #force_inline proc "contextless" (_end : linalg.point, _control : linalg.point) -> linalg.point {
    return CvtQuadraticToCubic0(_end, _control)
}

line_init :: proc "contextless" (_start: linalg.point, _end: linalg.point) -> shape_line {
	return shape_line{
		start = _start,
		control0 = {},
		control1 = {},
		end = _end,
		type = .Line,
	}
}

quadratic_init :: proc "contextless" (_start: linalg.point, _control01: linalg.point, _end: linalg.point) -> shape_line {
	return shape_line{
		start = _start,
		control0 = _control01,
		end = _end,
		type = .Quadratic,
	}
}

cubic_init :: proc "contextless" (_start: linalg.point, _control0: linalg.point, _control1: linalg.point, _end: linalg.point) -> shape_line {
	return shape_line{
		start = _start,
		control0 = _control0,
		control1 = _control1,
		end = _end,
		type = .Unknown,
	}
}

rect_line_init :: proc "contextless" (_rect: linalg.rect) -> [4]shape_line {
	return [4]shape_line{
		line_init(linalg.point{_rect.left, _rect.top}, linalg.point{_rect.left, _rect.bottom}),
		line_init(linalg.point{_rect.left, _rect.bottom}, linalg.point{_rect.right, _rect.bottom}),
		line_init(linalg.point{_rect.right, _rect.bottom}, linalg.point{_rect.right, _rect.top}),
		line_init(linalg.point{_rect.right, _rect.top}, linalg.point{_rect.left, _rect.top}),
	}
}

round_rect_line_init :: proc "contextless" (_rect: linalg.rect, _radius: f32) -> [8]shape_line {
	r := _radius
	// Clamp radius to fit within rect
	half_width := (_rect.right - _rect.left) * 0.5
	half_height := abs(_rect.bottom - _rect.top) * 0.5
	r = min(r, min(half_width, half_height))
	
	t: f32 = (4.0 / 3.0) * math.tan_f32(math.PI / 8.0)
	tt := t * r
	
	// Corner centers
	top_left := linalg.point{_rect.left + r, _rect.top + r}
	top_right := linalg.point{_rect.right - r, _rect.top + r}
	bottom_right := linalg.point{_rect.right - r, _rect.bottom - r}
	bottom_left := linalg.point{_rect.left + r, _rect.bottom - r}
	
	return [8]shape_line{
		// Top-left corner (cubic) - counter-clockwise: from top to left
		// Note: y increases upward, _rect.top is top (larger y), _rect.bottom is bottom (smaller y)
		cubic_init(
			linalg.point{_rect.left + r, _rect.top},
			linalg.point{_rect.left + r - tt, _rect.top},
			linalg.point{_rect.left, _rect.top - r + tt},
			linalg.point{_rect.left, _rect.top - r},
		),
		// Left line - counter-clockwise: from top to bottom (y decreases)
		line_init(
			linalg.point{_rect.left, _rect.top - r},
			linalg.point{_rect.left, _rect.bottom + r},
		),
		// Bottom-left corner (cubic) - counter-clockwise: from left to bottom
		cubic_init(
			linalg.point{_rect.left, _rect.bottom + r},
			linalg.point{_rect.left, _rect.bottom + r - tt},
			linalg.point{_rect.left + r - tt, _rect.bottom},
			linalg.point{_rect.left + r, _rect.bottom},
		),
		// Bottom line - counter-clockwise: from left to right
		line_init(
			linalg.point{_rect.left + r, _rect.bottom},
			linalg.point{_rect.right - r, _rect.bottom},
		),
		// Bottom-right corner (cubic) - counter-clockwise: from bottom to right
		cubic_init(
			linalg.point{_rect.right - r, _rect.bottom},
			linalg.point{_rect.right - r + tt, _rect.bottom},
			linalg.point{_rect.right, _rect.bottom + r - tt},
			linalg.point{_rect.right, _rect.bottom + r},
		),
		// Right line - counter-clockwise: from bottom to top (y increases)
		line_init(
			linalg.point{_rect.right, _rect.bottom + r},
			linalg.point{_rect.right, _rect.top - r},
		),
		// Top-right corner (cubic) - counter-clockwise: from right to top
		cubic_init(
			linalg.point{_rect.right, _rect.top - r},
			linalg.point{_rect.right, _rect.top - r + tt},
			linalg.point{_rect.right - r + tt, _rect.top},
			linalg.point{_rect.right - r, _rect.top},
		),
		// Top line - counter-clockwise: from right to left
		line_init(
			linalg.point{_rect.right - r, _rect.top},
			linalg.point{_rect.left + r, _rect.top},
		),
	}
}

circle_cubic_init :: proc "contextless" (_center: linalg.point, _r: f32) -> [4]shape_line {
	t: f32 = (4.0 / 3.0) * math.tan_f32(math.PI / 8.0)
	tt := t * _r
	return [4]shape_line{
		cubic_init(
			linalg.point{_center.x - _r, _center.y},
			linalg.point{_center.x - _r, _center.y - tt},
			linalg.point{_center.x - tt, _center.y - _r},
			linalg.point{_center.x, _center.y - _r},
		),
		cubic_init(
			linalg.point{_center.x, _center.y - _r},
			linalg.point{_center.x + tt, _center.y - _r},
			linalg.point{_center.x + _r, _center.y - tt},
			linalg.point{_center.x + _r, _center.y},
		),
		cubic_init(
			linalg.point{_center.x + _r, _center.y},
			linalg.point{_center.x + _r, _center.y + tt},
			linalg.point{_center.x + tt, _center.y + _r},
			linalg.point{_center.x, _center.y + _r},
		),
		cubic_init(
			linalg.point{_center.x, _center.y + _r},
			linalg.point{_center.x - tt, _center.y + _r},
			linalg.point{_center.x - _r, _center.y + tt},
			linalg.point{_center.x - _r, _center.y},
		),
	}
}

ellipse_cubic_init :: proc "contextless" (_center: linalg.point, _rxy: linalg.point) -> [4]shape_line {
	t: f32 = (4.0 / 3.0) * math.tan_f32(math.PI / 8.0)
	ttx := t * _rxy.x
	tty := t * _rxy.y
	return [4]shape_line{
		cubic_init(
			linalg.point{_center.x - _rxy.x, _center.y},
			linalg.point{_center.x - _rxy.x, _center.y - tty},
			linalg.point{_center.x - ttx, _center.y - _rxy.y},
			linalg.point{_center.x, _center.y - _rxy.y},
		),
		cubic_init(
			linalg.point{_center.x, _center.y - _rxy.y},
			linalg.point{_center.x + ttx, _center.y - _rxy.y},
			linalg.point{_center.x + _rxy.x, _center.y - tty},
			linalg.point{_center.x + _rxy.x, _center.y},
		),
		cubic_init(
			linalg.point{_center.x + _rxy.x, _center.y},
			linalg.point{_center.x + _rxy.x, _center.y + tty},
			linalg.point{_center.x + ttx, _center.y + _rxy.y},
			linalg.point{_center.x, _center.y + _rxy.y},
		),
		cubic_init(
			linalg.point{_center.x, _center.y + _rxy.y},
			linalg.point{_center.x - ttx, _center.y + _rxy.y},
			linalg.point{_center.x - _rxy.x, _center.y + tty},
			linalg.point{_center.x - _rxy.x, _center.y},
		),
	}
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

raw_shape_clone :: proc (self:^raw_shape, allocator := context.allocator) -> (res:^raw_shape = nil, err: mem.Allocator_Error) #optional_allocator_error {
    res = new(raw_shape, allocator) or_return
    defer if err != nil {
        free(res, allocator)
        res = nil
    }

    res.vertices = mem.make_non_zeroed_slice([]shape_vertex2d, len(self.vertices), allocator) or_return
    defer if err != nil do delete(res.vertices, allocator)

    res.indices = mem.make_non_zeroed_slice([]u32, len(self.indices), allocator) or_return

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

    // Assign params to temps, then internal calculation in f64
    start := [2]f64{f64(_start[0]), f64(_start[1])}
    c0    := [2]f64{f64(_control0[0]), f64(_control0[1])}
    c1    := [2]f64{f64(_control1[0]), f64(_control1[1])}
    end   := [2]f64{f64(_end[0]), f64(_end[1])}

    cross_1 := [3]f64{end[1] - c1[1],     c1[0] - end[0],     end[0] * c1[1] - end[1] * c1[0]}
    cross_2 := [3]f64{start[1] - end[1],  end[0] - start[0],  start[0] * end[1] - start[1] * end[0]}
    cross_3 := [3]f64{c0[1] - start[1],    start[0] - c0[0],   c0[0] * start[1] - c0[1] * start[0]}

    a1 := start[0] * cross_1[0]  + start[1] * cross_1[1]  + cross_1[2]
    a2 := c0[0] * cross_2[0]      + c0[1] * cross_2[1]     + cross_2[2]
    a3 := c1[0] * cross_3[0]      + c1[1] * cross_3[1]     + cross_3[2]

    d0 := a1 - 2 * a2 + 3 * a3
    d1 := -a2 + 3 * a3
    d2 := 3 * a3

    outD[0] = T(d0)
    outD[1] = T(d1)
    outD[2] = T(d2)

    D     := 3 * d1 * d1 - 4 * d2 * d0
    discr := d0 * d0 * D

    if discr >= -math.epsilon(f64) && discr <= math.epsilon(f64) {
        if d0 == 0.0 && d1 == 0.0 {
            if d2 == 0.0 {
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
    color:linalg.point3dw,
    pts:[]linalg.point,
    type:curve_type,
    _subdiv :f32 = 0.0,
    _repeat :int = -1) -> shape_error {

    assert(_subdiv >= 0)

    curveType := type
    err:shape_error = nil

    reverse := false
    outD:[3]f32 = {0, 0, 0}
    if curveType != .Line && curveType != .Quadratic {
        curveType, err, outD = GetCubicCurveType(pts[0], pts[1], pts[2], pts[3])
        if err != nil do return err
    } else if curveType == .Quadratic && len(pts) == 3 {
		if _subdiv == 0.0 {
            vlen :u32 = u32(len(vertList))
            if linalg.GetPolygonOrientation(pts) == .CounterClockwise {
                non_zero_append(vertList, shape_vertex2d{
                    uvw = {0,0,0},
                    pos = pts[0],
                    color = color,
					edge_boundary = {0,0,0,2},
                })
                non_zero_append(vertList, shape_vertex2d{
                    uvw = {-0.5,0,0.5},
                    pos = pts[1],
                    color = color,
					edge_boundary = {0,0,0,2},
                })
                non_zero_append(vertList, shape_vertex2d{
                    uvw = {-1,-1,1},
                    pos = pts[2],
                    color = color,
					edge_boundary = {0,0,0,2},
                })
            } else {
                non_zero_append(vertList, shape_vertex2d{
                    uvw = {0,0,0},
                    pos = pts[0],
                    color = color,
					edge_boundary = {0,0,0,2},
                })
                non_zero_append(vertList, shape_vertex2d{
                    uvw = {0.5,0,0.5},
                    pos = pts[1],
                    color = color,
					edge_boundary = {0,0,0,2},
                })
                non_zero_append(vertList, shape_vertex2d{
                    uvw = {1,1,1},
                    pos = pts[2],
                    color = color,
					edge_boundary = {0,0,0,2},
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
                intrinsics.trap()
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

    appendLine :: proc (vertList:^[dynamic]shape_vertex2d, indList:^[dynamic]u32, color:linalg.point3dw, pts:[]linalg.point, F:matrix[4,4]f32) {
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
    appendLine(vertList, indList, color,pts[:len(pts)], F)

    if len(pts) == 3 {
        non_zero_append(outPoly, CurveStruct{pts[0], false}, CurveStruct{pts[1], true})
    } else {
        non_zero_append(outPoly, CurveStruct{pts[0], false}, CurveStruct{pts[1], true}, CurveStruct{pts[2], true})
    }

    return nil
}

@(private="file") CurveStruct :: struct {
    p:linalg.point,
    isCurve:bool,
}

shapes_compute_polygon :: proc(poly:^shapes, allocator := context.allocator) -> (res:^raw_shape = nil, err:shape_error = nil) {
	__arena: mem.Dynamic_Arena = {}
	mem.dynamic_arena_init(&__arena, context.temp_allocator,context.temp_allocator)
	arena := mem.dynamic_arena_allocator(&__arena)
	defer mem.dynamic_arena_destroy(&__arena)

    vertList:[dynamic]shape_vertex2d = mem.make_non_zeroed([dynamic]shape_vertex2d, arena)
    indList:[dynamic]u32 = mem.make_non_zeroed_dynamic_array([dynamic]u32, arena)

    res = mem.new_non_zeroed(raw_shape, allocator) or_return
	defer if err != nil do free(res, allocator)

    defer if err != nil {
        free(res, allocator)
        res = nil
    }

    shapes_compute_polygon_in :: proc(vertList:^[dynamic]shape_vertex2d, indList:^[dynamic]u32, poly:^shapes, allocator : runtime.Allocator, arena : mem.Allocator) -> (err:shape_error = nil) {	
        outPoly:[][dynamic]CurveStruct = mem.make_non_zeroed([][dynamic]CurveStruct, len(poly.nodes), 64, arena)
        outPoly2:[dynamic]linalg.point = mem.make_non_zeroed([dynamic]linalg.point, arena)
        outPoly2N:[]u32 = mem.make_non_zeroed([]u32, len(poly.nodes), 64, arena)
        for &o in outPoly {
            o = make([dynamic]CurveStruct, arena)
        }

        poly_idx :u32 = 0
        for node in poly.nodes {
            if node.color.a > 0 {
				for line in node.lines {
					if line.type == .Line {
						non_zero_append(&outPoly[poly_idx], CurveStruct{line.start, false})
					} else if line.type == .Quadratic {
						pts := [3]linalg.point{line.start, line.control0, line.end}
						err = _Shapes_ComputeLine(
							vertList,
							indList,
							&outPoly[poly_idx],
							node.color,
							pts[:],
							.Quadratic, 0.5)
						if err != nil do return
					} else {
						pts := [4]linalg.point{line.start, line.control0, line.control1, line.end}
						err = _Shapes_ComputeLine(
							vertList,
							indList,
							&outPoly[poly_idx],
							node.color,
							pts[:],
							.Unknown, 0.5)//TODO (xfitgd) 일단은 0.5로 고정
						if err != nil do return
					}
				}
            }
			poly_idx += 1
        }

        for ps, psi in outPoly {
            if len(ps) == 0 do continue
            np :u32 = 0

            pT := mem.make_non_zeroed_dynamic_array([dynamic]linalg.point, arena )
            for p in ps {
                if !p.isCurve {
                    non_zero_append(&pT, p.p)
                }
            }

            for p, i in ps {
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

            outPoly2N[psi] = np
        }
        if len(outPoly2) == 0 do return

        indicesT, tErr := poly2tri.TrianguatePolygons(outPoly2[:], outPoly2N[:], arena)
        defer delete(indicesT, arena)
        
        if tErr != poly2tri.Trianguate_Error.None {
            err = tErr
            return
        }

		vertLen := u32(len(vertList))
		startIdx :u32= 0
		for psi in 0..<len(outPoly2N) {
			endIdx := startIdx + outPoly2N[psi]
			for t in startIdx..<endIdx {
				non_zero_append(vertList, shape_vertex2d{ pos = outPoly2[t], 
					color = poly.nodes[psi].color, edge_boundary = {0, 0, 0, 1} })
			}
			startIdx = endIdx
		}
		for t in 0..<len(indicesT) {
			non_zero_append(indList, indicesT[t] + vertLen)
		}
        return
    }


    has_fill := false
    for node in poly.nodes {
        if node.color.a > 0 {
            has_fill = true
            break
        }
    }
    if has_fill {
        err = shapes_compute_polygon_in(&vertList, &indList, poly, allocator, arena)
        if err != nil do return
    }

    has_stroke := false
    for node in poly.nodes {
        if node.stroke_color.a > 0 && node.thickness > 0 {
            has_stroke = true
            break
        }
	}
    
    if has_stroke {
        // 스트로크를 위한 새로운 shapes 생성
        total_stroke_polygons := len(poly.nodes) * 2
        
        stroke_nodes := mem.make_non_zeroed([]shape_node, total_stroke_polygons, 64,arena)
        
        node_idx := 0
        for node in poly.nodes {
            if node.stroke_color.a > 0 && node.thickness > 0 {	
				node_len :u32 = auto_cast len(node.lines)
				poly_points := mem.make_non_zeroed([]linalg.point, node_len, 64, arena)
				for i:u32 = 0; i < node_len; i += 1 {
					poly_points[i] = node.lines[i].start
				}
				poly_ori := linalg.GetPolygonOrientation(poly_points[:])
				
				// 외부 스트로크
				outer_lines := mem.make_non_zeroed([]shape_line, node_len, 64, arena)

				set_line_points_outer :: proc "contextless" (out_line:^shape_line, line:shape_line, prev_line:shape_line, next_line:shape_line, thickness:f32, poly_ori:linalg.PolyOrientation) {
					current_point := line.start
					next_point:linalg.point
					prev_point :linalg.point
					control0, control1:linalg.point = {0,0}, {0,0}

					#partial switch line.type {
						case .Line:next_point = next_line.start
						case:next_point = line.control0
					}
					#partial switch prev_line.type {
						case .Line:prev_point = prev_line.start
						case .Quadratic:prev_point = prev_line.control0
						case:prev_point = prev_line.control1
					}
					start_point := linalg.LineExtendPoint(prev_point, current_point, next_point, thickness, poly_ori)

					#partial switch line.type {
						case .Line:
						case .Quadratic:
							current_point = line.control0
							prev_point = line.start
							next_point = line.end  // control0 → end direction
							control0 = linalg.LineExtendPoint(prev_point, current_point, next_point, thickness, poly_ori)
						case:
							current_point = line.control0
							prev_point = line.start
							next_point = line.control1
							control0 = linalg.LineExtendPoint(prev_point, current_point, next_point, thickness, poly_ori)
					}

					#partial switch line.type {
						case .Line:
						case .Quadratic:
						case:
							current_point = line.control1
							prev_point = line.control0
							next_point = line.end  // control1 → end direction
							control1 = linalg.LineExtendPoint(prev_point, current_point, next_point, thickness, poly_ori)
					}

					out_line^ = shape_line{
						start = start_point,
						control0 = control0,
						control1 = control1,
						type = line.type,
					}
				}

				for i:u32 = 0; i < node_len; i += 1 {
					line := node.lines[i]
					prev_idx := i == 0 ? node_len - 1 : i - 1
					next_idx := i == node_len - 1 ? 0 : i + 1
					prev_line := node.lines[prev_idx]
					next_line := node.lines[next_idx]

					set_line_points_outer(&outer_lines[i], line, prev_line, next_line, 
						poly_ori == .Clockwise ? -node.thickness : node.thickness, poly_ori)
				}
				// Convert shape_lines to CurveStruct points
				shape_lines_to_points :: proc(lines: []shape_line, out_points: ^[dynamic]CurveStruct) {
					for line in lines {
						non_zero_append(out_points, CurveStruct{line.start, false})
						#partial switch line.type {
							case .Quadratic:
								non_zero_append(out_points, CurveStruct{line.control0, true})
							case .Line:
							case:  // Cubic
								non_zero_append(out_points, CurveStruct{line.control0, true})
								non_zero_append(out_points, CurveStruct{line.control1, true})
						}
					}
				}
				
				merge_intersecting_points :: proc (in_points: []CurveStruct, out_points: ^[dynamic]CurveStruct, allocator: runtime.Allocator) {
					if len(in_points) < 4 {
						for p in in_points {
							non_zero_append(out_points, p)
						}
						return
					}
					new_points := make([dynamic]CurveStruct, len(in_points), allocator)
					mem.copy_non_overlapping(&new_points[0], &in_points[0], len(in_points) * size_of(CurveStruct))
					
					for {
						found := false
						BREAK: for i := 0; i < len(new_points); i += 1 {
							next_i := (i + 1) % len(new_points)
							a1 := new_points[i].p
							a2 := new_points[next_i].p
							
							for j := (i + 2) % len(new_points);;j = (j + 1) % len(new_points){
								next_j :=  (j + 1) % len(new_points)
								if next_j == i {
									break
								}
								
								b1 := new_points[j].p
								b2 := new_points[next_j].p
								
								_, intersects, intersection := linalg.LinesIntersect2(a1, a2, b1, b2)
								
								if intersects {
									if next_i < j {
										remove_range(&new_points, next_i, j + 1)
									} else {
										remove_range(&new_points, next_j, i + 1)
									}
									found = true
									break BREAK
								}
							}
						}
						if !found do break
						if len(new_points) < 3 {
							return
						}
					}
					for p in new_points {
						non_zero_append(out_points, p)
					}
				}
				
				// Convert CurveStruct points back to shape_lines (closed polygon)
				points_to_shape_lines :: proc(points: []CurveStruct, out_lines: ^[dynamic]shape_line) {
					points_len := len(points)
					if points_len < 3 do return
					
					// Helper to get point with wrap-around for closed polygon
					get_point :: proc(pts: []CurveStruct, idx: int) -> CurveStruct {
						return pts[idx % len(pts)]
					}
					
					i := 0
					for i < points_len {
						// Find how many consecutive curve points follow
						curve_count := 0
						for j := 1; j < points_len; j += 1 {
							if get_point(points, i + j).isCurve {
								curve_count += 1
							} else {
								break
							}
						}
						
						if curve_count == 2 {
							// Cubic: start, ctrl0, ctrl1, end
							non_zero_append(out_lines, shape_line{
								start = get_point(points, i).p,
								control0 = get_point(points, i + 1).p,
								control1 = get_point(points, i + 2).p,
								end = get_point(points, i + 3).p,
								type = .Unknown,  // Cubic
							})
							i += 3
						} else if curve_count == 1 {
							// Quadratic: start, ctrl0, end
							non_zero_append(out_lines, shape_line{
								start = get_point(points, i).p,
								control0 = get_point(points, i + 1).p,
								control1 = {0,0},
								end = get_point(points, i + 2).p,
								type = .Quadratic,
							})
							i += 2
						} else {
							// Line: start, end
							non_zero_append(out_lines, shape_line{
								start = get_point(points, i).p,
								control0 = {0,0},
								control1 = {0,0},
								end = get_point(points, i + 1).p,
								type = .Line,
							})
							i += 1
						}
					}
				}
				
				// Process outer stroke
				out_points := mem.make_non_zeroed([dynamic]CurveStruct, arena)
				shape_lines_to_points(outer_lines, &out_points)
				
				out_points2 := mem.make_non_zeroed([dynamic]CurveStruct, arena)
				merge_intersecting_points(out_points[:], &out_points2, arena)

				if len(out_points2) < 3 {
				} else {			
					outer_lines2 := mem.make_non_zeroed([dynamic]shape_line, arena)
					points_to_shape_lines(out_points2[:], &outer_lines2)
					
					stroke_nodes[node_idx] = shape_node{
						lines = outer_lines2[:],
						color = node.stroke_color,
						stroke_color = {},
						thickness = 0,
					}
					node_idx += 1
				}
				
				// 내부 스트로크
				inner_lines := mem.make_aligned([]shape_line, node_len, 64, arena)	
				inner_lines2 := mem.make_aligned([]shape_line, node_len, 64, arena)

				for i:u32 = 0; i < node_len; i += 1 {
					origin_line := node.lines[node_len - 1 - i]
					inner_lines[i].start = origin_line.end
					inner_lines[i].end = origin_line.start
					#partial switch origin_line.type {
						case .Quadratic:
							inner_lines[i].control0 = origin_line.control0
						case:
							inner_lines[i].control1 = origin_line.control0
							inner_lines[i].control0 = origin_line.control1
					}
					inner_lines[i].type = origin_line.type
				}

				for i:u32 = 0; i < node_len; i += 1 {
					line := inner_lines[i]
					prev_idx := i == 0 ? node_len - 1 : i - 1
					next_idx := i == node_len - 1 ? 0 : i + 1
					prev_line := inner_lines[prev_idx]
					next_line := inner_lines[next_idx]

					set_line_points_outer(&inner_lines2[i], line, prev_line, next_line, 
						poly_ori == .Clockwise ? node.thickness : -node.thickness,
						poly_ori == .Clockwise ? .CounterClockwise : .Clockwise)
				}
				
				//Process inner stroke
				in_points := mem.make_non_zeroed([dynamic]CurveStruct, arena)
				shape_lines_to_points(inner_lines2, &in_points)
				
				in_points2 := mem.make_non_zeroed([dynamic]CurveStruct, arena)
				merge_intersecting_points(in_points[:], &in_points2, arena)
				
				if len(in_points2) < 3 {
				} else {			
					inner_lines3 := mem.make_non_zeroed([dynamic]shape_line, arena)
					points_to_shape_lines(in_points2[:], &inner_lines3)
					
					stroke_nodes[node_idx] = shape_node{
						lines = inner_lines3[:],
						color = node.stroke_color,
						stroke_color = {},
						thickness = 0,
					}
					node_idx += 1
				}
			}
        }
        
        polyT := shapes{
            nodes = stroke_nodes[:node_idx],
        }
        
        err = shapes_compute_polygon_in(&vertList, &indList, &polyT, allocator, arena)
        if err != nil do return
    }

    res.vertices = mem.make_non_zeroed([]shape_vertex2d, len(vertList), 64, allocator) or_return
    defer if err != nil do delete(res.vertices, allocator)
	res.indices = mem.make_non_zeroed([]u32, len(indList), 64, allocator) or_return

    intrinsics.mem_copy_non_overlapping(&res.vertices[0], &vertList[0], len(vertList) * size_of(shape_vertex2d))
    intrinsics.mem_copy_non_overlapping(&res.indices[0], &indList[0], len(indList) * size_of(u32))

    return
}

poly_transform_matrix :: proc "contextless" (inout_poly: ^shapes, F: linalg.matrix44) {
	for &node in inout_poly.nodes {
		for &line in node.lines {
			start := linalg.mul(F, linalg.point3dw{line.start.x, line.start.y, 0, 1})
			control0 := linalg.mul(F, linalg.point3dw{line.control0.x, line.control0.y, 0, 1})
			control1 := linalg.mul(F, linalg.point3dw{line.control1.x, line.control1.y, 0, 1})
			end := linalg.mul(F, linalg.point3dw{line.end.x, line.end.y, 0, 1})
			line.start = linalg.point{start.x, start.y} / start.w
			line.control0 = linalg.point{control0.x, control0.y} / control0.w
			line.control1 = linalg.point{control1.x, control1.y} / control1.w
			line.end = linalg.point{end.x, end.y} / end.w
		}
	}
}