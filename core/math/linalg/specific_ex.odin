package linalg

import "base:builtin"
import "base:intrinsics"
import "core:math"
import "core:mem"

RectI :: Rect_(i32)
RectU :: Rect_(u32)
RectF :: Rect_(f32)

PointF :: Vector2f32
Point3DF :: Vector3f32
Point3DwF :: Vector4f32
PointI :: [2]i32
PointU :: [2]u32
PointF64 :: [2]f64
Matrix :: Matrix4x4f32


Rect_ :: struct($T: typeid) where intrinsics.type_is_numeric(T) {
	pos:  [2]T,
	size: [2]T,
}


__Rect_Init :: #force_inline proc "contextless"(pos: [2]$T, size: [2]T) -> Rect_(T) {
	res: Rect_(T)
	res.pos = pos
	res.size = size
	return res
}

__Rect_Init2 :: #force_inline proc "contextless"(x: $T, y: T, width: T, height: T) -> Rect_(T) {
	res: Rect_(T)
	res.pos = [2]T{x, y}
	res.size = [2]T{width, height}
	return res
}

Rect_Init_LTRB :: #force_inline proc "contextless"(left: $T, right: T, top: T, bottom: T) -> Rect_(T) {
	res: Rect_(T)
	res.pos = [2]T{left, top}
	res.size = [2]T{right - left, top - bottom}
	return res
}


Rect_Init :: proc {
	__Rect_Init,
	__Rect_Init2,
}

//returns a rect whose centre point is the position
Rect_GetFromCenter :: #force_inline proc "contextless" (_pos: [2]$T, _size: [2]T) -> Rect_(T)  {
	res: Rect_(T)
	res.pos = _pos - _size / 2
	res.size = _size
	return res
}
//TODO (xfitgd)
Rect_MulMatrix :: proc (_r: RectF, _mat: Matrix) -> RectF #no_bounds_check {
	panic("")
}
//TODO (xfitgd)
Rect_DivMatrix :: proc (_r: RectF, _mat: Matrix) -> RectF #no_bounds_check {
	panic("")
}
Rect_Right :: #force_inline proc "contextless" (_r: Rect_($T)) -> T {
	return _r.pos.x + _r.size.x
}
Rect_Bottom :: #force_inline proc "contextless" (_r: Rect_($T)) -> T {
	return _r.pos.y + _r.size.y
}
Rect_RightBottom :: #force_inline proc "contextless" (_r: Rect_($T)) -> [2]T {
	return _r.pos + _r.size
}
Rect_And :: #force_inline proc "contextless" (_r1: Rect_($T), _r2: Rect_(T)) -> (Rect_(T), bool) #optional_ok #no_bounds_check {
	res: Rect_(T)
	for _, i in res.pos {
		res.pos[i] = max(_r1.pos[i], _r2.pos[i])
		res.size[i] = min(Rect_RightBottom(_r1)[i], Rect_RightBottom(_r2)[i])
		if res.size[i] <= res.pos[i] do return {}, false
		else do res.size[i] -= res.pos[i]
	}
	return res, true
}
Rect_Or :: #force_inline proc "contextless" (_r1: Rect_($T), _r2: Rect_(T)) -> Rect_(T) #no_bounds_check {
	if _r1.size.x == 0 || _r1.size.y == 0 do return _r2
	if _r2.size.x == 0 || _r2.size.y == 0 do return _r1

	res: Rect_(T)

	for _, i in res.pos {
		res.pos[i] = min(_r1.pos[i], _r2.pos[i])
		res.size[i] = max(Rect_RightBottom(_r1)[i], Rect_RightBottom(_r2)[i])
	}
	return res
}
Rect_PointIn :: #force_inline proc "contextless" (_r: Rect_($T), p: [2]T) -> bool #no_bounds_check {
	for _, i in _r.pos {
		if _r.pos[i] > p[i] do return false
		if Rect_RightBottom(_r)[i] < p[i] do return false
	}
	return true
}

Rect_Move :: #force_inline proc "contextless" (_r: Rect_($T), p: [2]T) -> Rect_(T) #no_bounds_check {
	res: Rect_(T)
	for _, i in _r.pos {
		res.pos[i] = _r.pos[i] + p[i]
	}
	res.size = _r.size
	return res
}

PointInTriangle :: proc "contextless" (p : [2]$T, a : [2]T, b : [2]T, c : [2]T) -> bool where intrinsics.type_is_float(T){
	x0 := c.x - a.x
	y0 := c.y - a.y
	x1 := b.x - a.x
	y1 := b.y - a.y
	x2 := p.x - a.x
	y2 := p.y - a.y

	dot00 := x0 * x0 + y0 * y0
	dot01 := x0 * x1 + y0 * y1
	dot02 := x0 * x2 + y0 * y2
	dot11 := x1 * x1 + y1 * y1
	dot12 := x1 * x2 + y1 * y2
	denominator := dot00 * dot11 - dot01 * dot01
	if (denominator == 0.0) do return false
	// Compute
	inverseDenominator := 1.0 / denominator
	u := (dot11 * dot02 - dot01 * dot12) * inverseDenominator
	v := (dot00 * dot12 - dot01 * dot02) * inverseDenominator

	return (u > 0.0) && (v > 0.0) && (u + v < 1.0)
}

PointInLine :: proc "contextless" (p:[2]$T, l0:[2]T, l1:[2]T) -> (bool, T) where intrinsics.type_is_float(T) {
	A := (l0.y - l1.y) / (l0.x - l1.x)
	B := l0.y - A * l0.x

	pY := A * p.x + B
	res := p.y >= pY - epsilon(T) && p.y <= pY + epsilon(T) 
	t :T = 0.0
	if res {
		minX := min(l0.x, l1.x)
		maxX := max(l0.x, l1.x)
		t = (p.x - minX) / (maxX - minX)
	}

	return res &&
		p.x >= min(l0.x, l1.x) &&
		p.x <= max(l0.x, l1.x) &&
		p.y >= min(l0.y, l1.y) &&
		p.y <= max(l0.y, l1.y), t
}

PointDeltaInLine :: proc "contextless" (p:[2]$T, l0:[2]T, l1:[2]T) -> T where intrinsics.type_is_float(T) {
	A := (l0.y - l1.y) / (l0.x - l1.x)
	B := l0.y - A * l0.x

	pp := NearestPointBetweenPointAndLine(p, l0, l1)

	pY := A * pp.x + B
	t :T = 0.0
	minX := min(l0.x, l1.x)
	maxX := max(l0.x, l1.x)
	t = (p.x - minX) / (maxX - minX)

	return t
}

PointInVector :: proc "contextless" (p:[2]$T, v0:[2]T, v1:[2]T) -> (bool, T) where intrinsics.type_is_float(T) {
	a := v1.y - v0.y
	b := v0.x - v1.x
	c := v1.x * v0.y + v0.x * v1.y
	res := a * p.x + b * p.y + c
	return res == 0, res
}

PointLineLeftOrRight :: #force_inline proc "contextless" (p : [2]$T, l0 : [2]T, l1 : [2]T) -> T where intrinsics.type_is_float(T) {
	return (l1.x - l0.x) * (p.y - l0.y) - (p.x - l0.x) * (l1.y - l0.y)
}

PointInPolygon :: proc "contextless" (p: [2]$T, polygon:[][2]T) -> bool where intrinsics.type_is_float(T) {
	crossProduct :: proc "contextless" (p1: [2]$T, p2 : [2]T, p3 : [2]T) -> T {
		return (p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x)
	}
	isPointOnSegment :: proc "contextless" (p: [2]$T, p1 : [2]T, p2 : [2]T) -> bool {
		return crossProduct(p1, p2, p) == 0 && p.x >= min(p1.x, p2.x) && p.x <= max(p1.x, p2.x) && p.y >= min(p1.y, p2.y) && p.y <= max(p1.y, p2.y)
	}
	windingNumber := 0
	for i in  0..<len(polygon) {
		p1 := polygon[i]
        p2 := polygon[(i + 1) % len(polygon)]

        if (isPointOnSegment(p, p1, p2)) {
            return false
        }

        if (p1.y <= p.y) {
            if (p2.y > p.y && crossProduct(p1, p2, p) > 0) {
                windingNumber += 1
            }
        } else {
            if (p2.y <= p.y && crossProduct(p1, p2, p) < 0) {
                windingNumber -= 1
            }
        }
	}
	return windingNumber != 0
}

CenterPointInPolygon :: proc "contextless" (polygon : [][2]$T) -> [2]T where intrinsics.type_is_float(T) {
	area :f32 = 0
	p : [2]T = {0,0}
	for i in 0..<len(polygon) {
		j := (i + 1) % len(polygon)
		factor := linalg.vector_cross2(polygon[i], polygon[j])
		area += factor
		p = (polygon[i] + polygon[j]) * splat_2(factor) + p
	}
	area = area / 2 * 6
	p *= splat_2(1 / area)
	return p
}

GetPolygonOrientation :: proc "contextless" (polygon : [][2]$T) -> PolyOrientation where intrinsics.type_is_float(T) {
	res :f32 = 0
	for i in 0..<len(polygon) {
		j := (i + 1) % len(polygon)
		factor := (polygon[j].x - polygon[i].x) * (polygon[j].y + polygon[i].y)
		res += factor
	}

	return res > 0 ? .Clockwise : .CounterClockwise
}

LineInPolygon :: proc "contextless" (a : [2]$T, b : [2]T, polygon : [][2]T, checkInsideLine := true) -> bool where intrinsics.type_is_float(T) {
	//Points a, b must all be inside the polygon so that line a, b and polygon line segments do not intersect, so b does not need to be checked.
	if checkInsideLine && PointInPolygon(a, polygon) do return true

	res : PointF
	ok:bool
	for i in 0..<len(polygon) {
		j := (i + 1) % len(polygon)
		ok, res = LinesIntersect(polygon[i], polygon[j], a, b)
		if ok {
			if a == res || b == res do continue
			return true
		}
	}
	return false
}

LinesIntersect :: proc "contextless" (a1 : [2]$T, a2 : [2]T, b1: [2]T, b2 : [2]T) -> bool where intrinsics.type_is_float(T) {
	Orientation :: proc "contextless" (p1 : [2]$T, p2 : [2]T, p3: [2]T) -> int {
		crossProduct := (p2.y - p1.y) * (p3.x - p2.x) - (p3.y - p2.y) * (p2.x - p1.x);
		return (crossProduct < 0.0) ? -1 : ((crossProduct > 0.0) ? 1 : 0);
	}
	return (Orientation(a1, a2, b1) != Orientation(a1, a2, b2) && Orientation(b1, b2, a1) != Orientation(b1, b2, a2));
}

// based on http://local.wasp.uwa.edu.au/~pbourke/geometry/lineline2d/, edgeA => "line a", edgeB => "line b"
LinesIntersect2 :: proc "contextless" (a1 : [2]$T, a2 : [2]T, b1: [2]T, b2 : [2]T) -> (bool, bool, [2]T) where intrinsics.type_is_float(T) {
	den :T = (b2.y - b1.y) * (a2.x - a1.x) - (b2.x - b1.x) * (a2.y - a1.y)
	if den == 0.0 {
		return false, false, {}
	}

	ua := ((b2.x - b1.x) * (a1.y - b1.y) - (b2.y - b1.y) * (a1.x - b1.x)) / den
	ub := ((a2.x - a1.x) * (a1.y - b1.y) - (a2.y - a1.y) * (a1.x - b1.x)) / den

	return true, ua >= 0.0 && ub >= 0.0 && ua <= 1.0 && ub <= 1.0, [2]T{a1.x + ua * (a2.x - a1.x), a1.y + ua * (a2.y - a1.y)}
}

//https://stackoverflow.com/a/73061541 잘못된? 부분 약간 수정
LineExtendPoint :: proc "contextless" (prev:[2]$T, cur:[2]T, next:[2]T, thickness:T, ccw:PolyOrientation) -> [2]T where intrinsics.type_is_float(T) {
	vn : [2]T = next - cur
	vnn : [2]T = normalize(vn)
	nnnX := vnn.y
	nnnY := -vnn.x

	ccw_ : T = (ccw == .Clockwise ? -1 : 1)
	vp : [2]T = cur - prev
	vpn: [2]T = normalize(vp)
	npnX := vpn.y 
	npnY := -vpn.x 

	bis := [2]T{(nnnX + npnX) * ccw_, (nnnY + npnY) * ccw_}
	bisn : [2]T = normalize(bis)
	bislen := thickness / intrinsics.sqrt((1 + nnnX * npnX + nnnY * npnY) / 2)

	return {cur.x + bislen * bisn.x, cur.y + bislen * bisn.y}
}

NearestPointBetweenPointAndLine :: proc "contextless" (p:[2]$T, l0:[2]T, l1:[2]T) -> [2]T where intrinsics.type_is_float(T) {
	AB := l1 - l0
	AC := p - l0

	return l0 + AB * (linalg.vector_dot(AB, AC) / linalg.vector_dot(AB, AB))
}

Circle :: struct(T:typeid) where intrinsics.type_is_float(T) {
	p : [2]T,
	radius : T,
}

CircleF :: Circle(f32)
CircleF64 :: Circle(f64)

PolyOrientation :: enum {
	Clockwise,
	CounterClockwise
}

OppPolyOrientation :: #force_inline proc "contextless" (ccw:PolyOrientation) -> PolyOrientation {
	return ccw == .Clockwise ? .CounterClockwise : .Clockwise
}

//TODO (xfitgd)
// //See https://github.com/Stanko/offset-polygon
// offsetPolygon :: proc (pts:[][2]$T, offset:T, allocator := context.allocator) -> [][2]T where intrinsics.type_is_float(T) {
// 	__Edge :: struct {
// 		v1:[2]T,
// 		v2:[2]T,
// 		outward_normal:[2]T,
// 		inward_normal:[2]T,
// 		idx:int,
// 	}
// 	__OffsetEdge :: struct {
// 		v1:[2]T,
// 		v2:[2]T,
// 	}
// 	__Polygon :: struct {
// 		vertices:[][2]T,
// 		edges:[]__Edge,
// 	}
// 	poly : __Polygon = createPolygon(pts)
// 	defer delete(poly.edges, context.temp_allocator)

// 	createPolygon :: proc (pts:[][2]$T) -> __Polygon {
// 		edges : []__Edge = mem.make_non_zeroed_slice([]__Edge, len(pts), context.temp_allocator)

// 		for i in 0..<len(pts) {
// 			v1 := pts[i]
// 			v2 := pts[(i + 1) % len(pts)]

// 			outward_normal := outward_edge_normal(v1, v2)
// 			inward_normal := inward_edge_normal(v1, v2)

// 			edge : __Edge = {
// 				v1,
// 				v2,
// 				outward_normal,
// 				inward_normal,
// 				i
// 			}
// 			edges[i] = edge
// 		}

// 		return __Polygon{ pts, edges }
// 	}

// 	outward_edge_normal :: #force_inline proc "contextless" (v1:[2]T, v2:[2]T) -> [2]T {
// 		out := inward_edge_normal(v1, v2)
// 		return [2]T{-out.x, -out.y}
// 	}

// 	// See http://paulbourke.net/geometry/pointlineplane/
// 	inward_edge_normal :: proc "contextless" (v1:[2]T, v2:[2]T) -> [2]T {
// 		d := v2 - v1
// 		len := math.sqrt(d.x * d.x + d.y * d.y)

// 		return [2]T{
// 			-d.y / len,
// 			d.x / len
// 		}
// 	}

// 	create_offset_edge :: #force_inline proc "contextless" (edge:__Edge, d:[2]T) -> __OffsetEdge {
// 		return __OffsetEdge{edge.v1 + d, edge.v2 + d}
// 	}

// 	out:[][2]T = mem.make_non_zeroed_slice([][2]T, len(pts), allocator)
// 	offset_edges : []__OffsetEdge = mem.make_non_zeroed_slice([]__OffsetEdge, len(pts), context.temp_allocator)
// 	defer delete(offset_edges, context.temp_allocator)

// 	if offset > 0 {
// 		for e, i in poly.edges {
// 			d := e.outward_normal * offset
// 			offset_edges[i] = create_offset_edge(e, d)
// 		}
// 	} else {
// 		for e, i in poly.edges {
// 			d := e.inward_normal * offset
// 			offset_edges[i] = create_offset_edge(e, d)
// 		}
// 	}

// 	for e, i in offset_edges {
// 		prev := offset_edges[(i + len(offset_edges) - 1) % len(offset_edges)]
// 		den, _, v := LinesIntersect2(prev.v1, prev.v2, e.v1, e.v2)
// 		if den {
// 			out[i] = v
// 		} else {
// 			out[i] = e.v1
// 		}
// 	}

// 	return out
// }

MirrorPoint :: #force_inline proc "contextless" (pivot : [2]$T, target : [2]T) -> [2]T where intrinsics.type_is_float(T) {
	return [2]T{2,2} * pivot - target
}

Area :: union($T: typeid) where intrinsics.type_is_numeric(T)  {
	Rect_(T),
	[][2]T,
}

AreaF :: Area(f32)
AreaF64 :: Area(f64)
AreaI :: Area(i32)

Area_PointIn :: #force_inline proc "contextless" (area:Area($T), pt:[2]T) -> bool where intrinsics.type_is_numeric(T) {
	switch a in area {
		case Rect_(T):return Rect_PointIn(a, pt)
		case [][2]T:return PointInPolygon(pt, a)
	}
	return false
}

xy_mirror_point :: #force_inline proc "contextless" (pivot : [2]$T, target : [2]T) -> [2]T where intrinsics.type_is_float(T) {
	return [2]T{2,2} * pivot - target
}