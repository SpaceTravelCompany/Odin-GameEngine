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
	rect: linalg.rect,
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