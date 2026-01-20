package svg

//! incomplete supports basic features not tested yet

import "core:encoding/xml"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:strings"
import "core:strconv"
import "core:fmt"
import "core:slice"
import "core:unicode"
import "base:intrinsics"
import "core:engine/geometry"

SVG :: struct {
	width:  string,
	height: string,
}

//! css not supported yet
FILL_AND_STROKE :: struct {
	fill:           Maybe(string),
	stroke:         Maybe(string),
	stroke_width:   Maybe(f32),
	//! Not supported yet
	stroke_linecap: Maybe(string),
	//! Not supported yet
	stroke_dasharray: Maybe(string),
	fill_opacity:   Maybe(f32),
	stroke_opacity: Maybe(f32),
}

PATH :: struct {
	d:         Maybe(string),
	fill_rule: Maybe(string),
	clip_rule: Maybe(string),
	_0:        FILL_AND_STROKE,
}

RECT :: struct {
	x:      Maybe(f32),
	y:      Maybe(f32),
	width:  Maybe(f32),
	height: Maybe(f32),
	rx:     Maybe(f32),
	ry:     Maybe(f32),
	_0:     FILL_AND_STROKE,
}

CIRCLE :: struct {
	cx: Maybe(f32),
	cy: Maybe(f32),
	r:  Maybe(f32),
	_0: FILL_AND_STROKE,
}

ELLIPSE :: struct {
	cx: Maybe(f32),
	cy: Maybe(f32),
	rx: Maybe(f32),
	ry: Maybe(f32),
	_0: FILL_AND_STROKE,
}

LINE :: struct {
	x1: Maybe(f32),
	y1: Maybe(f32),
	x2: Maybe(f32),
	y2: Maybe(f32),
	_0: FILL_AND_STROKE,
}

POLYLINE :: struct {
	points: []linalg.PointF,
	_0:     FILL_AND_STROKE,
}

POLYGON :: struct {
	points: []linalg.PointF,
	_0:     FILL_AND_STROKE,
}

CSS_COLOR :: enum(u32) {
	black = 0x000000,
	silver = 0xc0c0c0,
	white = 0xffffff,
	maroon = 0x800000,
	red = 0xff0000,
	purple = 0x800080,
	fuchsia = 0xff00ff,
	green = 0x008000,
	lime = 0x00ff00,
	olive = 0x808000,
	yellow = 0xffff00,
	navy = 0x000080,
	blue = 0x0000ff,
	teal = 0x008080,
	aqua = 0x00ffff,
	cyan = 0x00ffff,
	magenta = 0xff00ff,
	orange = 0xffa500,
	aliceblue = 0xf0f8ff,
	antiquewhite = 0xfaebd7,
	aquamarine = 0x7fffd4,
	azure = 0xf0ffff,
	beige = 0xf5f5dc,
	bisque = 0xffe4c4,
	blanchedalmond = 0xffebcd,
	blueviolet = 0x8a2be2,
	brown = 0xa52a2a,
	burlywood = 0xdeb887,
	cadetblue = 0x5f9ea0,
	chartreuse = 0x7fff00,
	chocolate = 0xd2691e,
	coral = 0xff7f50,
	cornflowerblue = 0x6495ed,
	cornsilk = 0xfff8dc,
	crimson = 0xdc143c,
	darkblue = 0x00008b,
	darkcyan = 0x008b8b,
	darkgoldenrod = 0xb8860b,
	darkgreen = 0x006400,
	darkgrey = 0xa9a9a9,
	darkgray = 0xa9a9a9,
	darkkhaki = 0xbdb76b,
	darkmagenta = 0x8b008b,
	darkolivegreen = 0x556b2f,
	darkorange = 0xff8c00,
	darkorchid = 0x9932cc,
	darkred = 0x8b0000,
	darksalmon = 0xe9967a,
	darkseagreen = 0x8fbc8f,
	darkslateblue = 0x483d8b,
	darkslategrey = 0x2f4f4f,
	darkturquoise = 0x00ced1,
	darkviolet = 0x9400d3,
	deeppink = 0xff1493,
	deepskyblue = 0x00bfff,
	dimgrey = 0x696969,
	dimgray = 0x696969,
	dodgerblue = 0x1e90ff,
	firebrick = 0xb22222,
	floralwhite = 0xfffaf0,
	forestgreen = 0x228b22,
	gainsboro = 0xdcdcdc,
	ghostwhite = 0xf8f8ff,
	gold = 0xffd700,
	goldenrod = 0xdaa520,
	greenyellow = 0xadff2f,
	grey = 0x808080,
	gray = 0x808080,
	honeydew = 0xf0fff0,
	hotpink = 0xff69b4,
	indianred = 0xcd5c5c,
	indigo = 0x4b0082,
	ivory = 0xfffff0,
	khaki = 0xf0e68c,
	lavender = 0xe6e6fa,
	lavenderblush = 0xfff0f5,
	lawngreen = 0x7cfc00,
	lemonchiffon = 0xfffacd,
	lightblue = 0xadd8e6,
	lightcoral = 0xf08080,
	lightcyan = 0xe0ffff,
	lightgoldenrodyellow = 0xfafad2,
	lightgreen = 0x90ee90,
	lightgrey = 0xd3d3d3,
	lightgray = 0xd3d3d3,
	lightpink = 0xffb6c1,
	lightsalmon = 0xffa07a,
	lightseagreen = 0x20b2aa,
	lightskyblue = 0x87cefa,
	lightslategrey = 0x778899,
	lightslategray = 0x778899,
	lightsteelblue = 0xb0c4de,
	lightyellow = 0xffffe0,
	limegreen = 0x32cd32,
	linen = 0xfaf0e6,
	mediumaquamarine = 0x66cdaa,
	mediumblue = 0x0000cd,
	mediumorchid = 0xba55d3,
	mediumpurple = 0x9370db,
	mediumseagreen = 0x3cb371,
	mediumslateblue = 0x7b68ee,
	mediumspringgreen = 0x00fa9a,
	mediumturquoise = 0x48d1cc,
	mediumvioletred = 0xc71585,
	midnightblue = 0x191970,
	mintcream = 0xf5fffa,
	mistyrose = 0xffe4e1,
	moccasin = 0xffe4b5,
	navajowhite = 0xffdead,
	oldlace = 0xfdf5e6,
	olivedrab = 0x6b8e23,
	orangered = 0xff4500,
	orchid = 0xda70d6,
	palegoldenrod = 0xeee8aa,
	palegreen = 0x98fb98,
	paleturquoise = 0xafeeee,
	palevioletred = 0xdb7093,
	papayawhip = 0xffefd5,
	peachpuff = 0xffdab9,
	peru = 0xcd853f,
	pink = 0xffc0cb,
	plum = 0xdda0dd,
	powderblue = 0xb0e0e6,
	rosybrown = 0xbc8f8f,
	royalblue = 0x4169e1,
	saddlebrown = 0x8b4513,
	salmon = 0xfa8072,
	sandybrown = 0xf4a460,
	seagreen = 0x2e8b57,
	seashell = 0xfff5ee,
	sienna = 0xa0522d,
	skyblue = 0x87ceeb,
	slateblue = 0x6a5acd,
	slategrey = 0x708090,
	slategray = 0x708090,
	snow = 0xfffafa,
	springgreen = 0x00ff7f,
	steelblue = 0x4682b4,
	tan = 0xd2b48c,
	thistle = 0xd8bfd8,
	tomato = 0xff6347,
	turquoise = 0x40e0d0,
	violet = 0xee82ee,
	wheat = 0xf5deb3,
	whitesmoke = 0xf5f5f5,
	yellowgreen = 0x9acd32,
	rebeccapurple = 0x663399,
}

__SVG_ERROR :: enum {
	NOT_INITIALIZED,
	OVERLAPPING_NODE,
	INVALID_NODE,
	UNSUPPORTED_FEATURE,
}

SVG_ERROR :: union {
	__SVG_ERROR,
	xml.Error,
}

svg_shape_ptr :: union #no_nil {
	^PATH,
	^RECT,
	^CIRCLE,
	^ELLIPSE,
	^LINE,
	^POLYLINE,
	^POLYGON,
    ^SVG,
}

svg_parser :: struct {
	arena_allocator: Maybe(mem.Allocator),
    __arena:         mem.Dynamic_Arena,
	svg:             SVG,
	path:            []PATH,
	rect:            []RECT,
	circle:          []CIRCLE,
	ellipse:         []ELLIPSE,
	line:            []LINE,
	polyline:        []POLYLINE,
	polygon:         []POLYGON,
	shape_ptrs:      []svg_shape_ptr,
	shapes:          geometry.shapes,
}

@private __svg_parser_data :: struct {
	svg:             SVG,
	path:            [dynamic]PATH,
	rect:            [dynamic]RECT,
	circle:          [dynamic]CIRCLE,
	ellipse:         [dynamic]ELLIPSE,
	line:            [dynamic]LINE,
	polyline:        [dynamic]POLYLINE,
	polygon:         [dynamic]POLYGON,
	shape_ptrs:      [dynamic]svg_shape_ptr,
}

@private __shapes :: struct {
	polys:[dynamic]linalg.PointF,
    n_polys:[dynamic]u32,
    n_types:[dynamic]u32,
    types:[dynamic]geometry.curve_type,
    colors:[dynamic]linalg.Point3DwF,
    strokeColors:[dynamic]linalg.Point3DwF,
    thickness:[dynamic]f32,
}

deinit :: proc(self: ^svg_parser) {
	if self.arena_allocator != nil {
		mem.dynamic_arena_destroy(&self.__arena)
		self.arena_allocator = nil
	}
}

@private _parse_fill_and_stroke :: proc (attribs: xml.Attribute, out: ^FILL_AND_STROKE, allocator: mem.Allocator) -> SVG_ERROR {
	err : bool = false
	
	switch attribs.key {
	case "fill":out.fill = strings.clone(attribs.val, allocator)
	case "stroke":out.stroke = strings.clone(attribs.val, allocator)
	case "stroke-width":out.stroke_width, err = strconv.parse_f32(attribs.val)
	case "fill-opacity":out.fill_opacity, err = strconv.parse_f32(attribs.val)
	case "stroke-opacity":out.stroke_opacity, err = strconv.parse_f32(attribs.val)
	}

	if err do return .INVALID_NODE
	return nil
}

@private _parse_point :: proc "contextless" (points: string, inout_idx: ^int) -> (result: linalg.PointF, err: SVG_ERROR = nil) {
	check_two_more_dots :: proc "contextless" (points: string, inout_idx: int, nonidx: int) -> int {
		found_dot := false
		for idx in inout_idx..<nonidx {
			if points[idx] == '.' {
				if !found_dot {
					found_dot = true
				} else {
					return idx//find and check two more dots.
				}
			}
		}
		return nonidx
	}

	// 숫자나 '-' 또는 '.' 문자가 처음 나타나는 위치 찾기
	idx_any := strings.index_any(points[inout_idx^:], "0123456789.-")
	if idx_any == -1 {
		err = .INVALID_NODE
		return
	}
	inout_idx^ += idx_any
	
	// 숫자나 '.'이 아닌 문자가 처음 나타나는 위치 찾기
	nonidx := inout_idx^ + 1
	for nonidx < len(points) {
		c := points[nonidx]
		if !(c >= '0' && c <= '9' || c == '.') {
			break
		}
		nonidx += 1
	}
	nonidx = check_two_more_dots(points, inout_idx^, nonidx)
	
	// x 좌표 파싱
	x, parse_ok_x := strconv.parse_f32(points[inout_idx^:nonidx])
	if !parse_ok_x {
		err = .INVALID_NODE
		return
	}
	
	// 다음 숫자 시작 위치 찾기
	idx_any = strings.index_any(points[nonidx:], "0123456789.-")
	if idx_any == -1 {
		err = .INVALID_NODE
		return
	}
	inout_idx^ = nonidx + idx_any
	
	// y 좌표의 끝 위치 찾기
	nonidx = inout_idx^ + 1
	for nonidx < len(points) {
		c := points[nonidx]
		if !(c >= '0' && c <= '9' || c == '.') {
			break
		}
		nonidx += 1
	}
	
	nonidx = check_two_more_dots(points, inout_idx^, nonidx)
	
	// y 좌표 파싱
	y, parse_ok_y := strconv.parse_f32(points[inout_idx^:nonidx])
	if !parse_ok_y {
		err = .INVALID_NODE
		return
	}
	
	inout_idx^ = nonidx
	result = linalg.PointF{x, y}
	return
}

@private _parse_points :: proc (points: string, allocator: mem.Allocator) -> (result: []linalg.PointF, err: SVG_ERROR) {
	result_ := mem.make_non_zeroed([dynamic]linalg.PointF, context.temp_allocator)
	defer delete(result_)

	i := 0
	for i < len(points) {
		non_zero_append(&result_, _parse_point(points, &i) or_return)
	}

	result = mem.make_non_zeroed([]linalg.PointF, len(result_), allocator)
	mem.copy_non_overlapping(&result[0], &result_[0], len(result_) * size_of(linalg.PointF))
	return result, nil
}

@private _parse_svg_element :: proc(xml_doc: ^xml.Document, idx: xml.Element_ID, out: ^__svg_parser_data, allocator: mem.Allocator) -> SVG_ERROR {
	e := &xml_doc.elements[idx]
	err : bool = false

	switch e.ident {
	case "svg":
		for a in e.attribs {
			switch a.key {
			case "width" : out.svg.width = strings.clone(a.val, allocator)
			case "height" : out.svg.height = strings.clone(a.val, allocator)
			}
		}
		non_zero_append(&out.shape_ptrs, &out.svg)
	case "path":
		non_zero_append(&out.path, PATH{})
		for a in e.attribs {
			switch a.key {
			case "d" : out.path[len(out.path) - 1].d = strings.clone(a.val, allocator)
			case "fill-rule" : out.path[len(out.path) - 1].fill_rule = strings.clone(a.val, allocator)
			case "clip-rule" : out.path[len(out.path) - 1].clip_rule = strings.clone(a.val, allocator)
			case : _parse_fill_and_stroke(a, &out.path[len(out.path) - 1]._0, allocator) or_return
			}
		}
		non_zero_append(&out.shape_ptrs, &out.path[len(out.path) - 1])
	case "rect":
		non_zero_append(&out.rect, RECT{})
		for a in e.attribs {
			switch a.key {
			case "x" : out.rect[len(out.rect) - 1].x, err = strconv.parse_f32(a.val)
			case "y" : out.rect[len(out.rect) - 1].y, err = strconv.parse_f32(a.val)
			case "width" : out.rect[len(out.rect) - 1].width, err = strconv.parse_f32(a.val)
			case "height" : out.rect[len(out.rect) - 1].height, err = strconv.parse_f32(a.val)
			case "rx" : out.rect[len(out.rect) - 1].rx, err = strconv.parse_f32(a.val)
			case "ry" : out.rect[len(out.rect) - 1].ry, err = strconv.parse_f32(a.val)
			case : _parse_fill_and_stroke(a, &out.rect[len(out.rect) - 1]._0, allocator) or_return
			}
		}
		non_zero_append(&out.shape_ptrs, &out.rect[len(out.rect) - 1])
	case "circle":
		non_zero_append(&out.circle, CIRCLE{})
		for a in e.attribs {
			switch a.key {
			case "cx" : out.circle[len(out.circle) - 1].cx, err = strconv.parse_f32(a.val)
			case "cy" : out.circle[len(out.circle) - 1].cy, err = strconv.parse_f32(a.val)
			case "r" : out.circle[len(out.circle) - 1].r, err = strconv.parse_f32(a.val)
			case : _parse_fill_and_stroke(a, &out.circle[len(out.circle) - 1]._0, allocator) or_return
			}
		}
		non_zero_append(&out.shape_ptrs, &out.circle[len(out.circle) - 1])
	case "ellipse":
		non_zero_append(&out.ellipse, ELLIPSE{})
		for a in e.attribs {
			switch a.key {
			case "cx" : out.ellipse[len(out.ellipse) - 1].cx, err = strconv.parse_f32(a.val)
			case "cy" : out.ellipse[len(out.ellipse) - 1].cy, err = strconv.parse_f32(a.val)
			case "rx" : out.ellipse[len(out.ellipse) - 1].rx, err = strconv.parse_f32(a.val)
			case "ry" : out.ellipse[len(out.ellipse) - 1].ry, err = strconv.parse_f32(a.val)
			case : _parse_fill_and_stroke(a, &out.ellipse[len(out.ellipse) - 1]._0, allocator) or_return
			}
		}
		non_zero_append(&out.shape_ptrs, &out.ellipse[len(out.ellipse) - 1])
	case "line":
		non_zero_append(&out.line, LINE{})
		for a in e.attribs {
			switch a.key {
			case "x1" : out.line[len(out.line) - 1].x1, err = strconv.parse_f32(a.val)
			case "y1" : out.line[len(out.line) - 1].y1, err = strconv.parse_f32(a.val)
			case "x2" : out.line[len(out.line) - 1].x2, err = strconv.parse_f32(a.val)
			case "y2" : out.line[len(out.line) - 1].y2, err = strconv.parse_f32(a.val)
			case : _parse_fill_and_stroke(a, &out.line[len(out.line) - 1]._0, allocator) or_return
			}
		}
		non_zero_append(&out.shape_ptrs, &out.line[len(out.line) - 1])
	case "polyline":
		non_zero_append(&out.polyline, POLYLINE{})
		for a in e.attribs {
			switch a.key {
			case "points" : out.polyline[len(out.polyline) - 1].points = _parse_points(a.val, allocator) or_return
			case : _parse_fill_and_stroke(a, &out.polyline[len(out.polyline) - 1]._0, allocator) or_return
			}
		}
		non_zero_append(&out.shape_ptrs, &out.polyline[len(out.polyline) - 1])
	case "polygon":
		non_zero_append(&out.polygon, POLYGON{})
		for a in e.attribs {
			switch a.key {
			case "points" : out.polygon[len(out.polygon) - 1].points = _parse_points(a.val, allocator) or_return
			case : _parse_fill_and_stroke(a, &out.polygon[len(out.polygon) - 1]._0, allocator) or_return
			}
		}	
		non_zero_append(&out.shape_ptrs, &out.polygon[len(out.polygon) - 1])
	}
	if err do return .INVALID_NODE

	for ee in e.value {
		switch v in ee {
		case xml.Element_ID:
			_parse_svg_element(xml_doc, v, out, allocator)
		case string:
			return nil//!svg xml not have value
		}
	}
	return nil
}

init_parse :: proc(svg_data: []u8, allocator: mem.Allocator = context.allocator) -> (parser: svg_parser, err: SVG_ERROR) {
	parser = {}
    mem.dynamic_arena_init(&parser.__arena, allocator,allocator)
	arena := mem.dynamic_arena_allocator(&parser.__arena)
	parser.arena_allocator = arena
	defer if err != nil {
		deinit(&parser)
	}

	// Parse XML document
	xml_doc, xml_err := xml.parse(svg_data, allocator = context.temp_allocator)
	defer xml.destroy(xml_doc)
	if xml_err != nil {
		err = xml_err
		return
	}

	data : __svg_parser_data = {}
	data.path = mem.make_non_zeroed([dynamic]PATH, context.temp_allocator)
	data.rect = mem.make_non_zeroed([dynamic]RECT, context.temp_allocator)
	data.circle = mem.make_non_zeroed([dynamic]CIRCLE, context.temp_allocator)
	data.ellipse = mem.make_non_zeroed([dynamic]ELLIPSE, context.temp_allocator)
	data.line = mem.make_non_zeroed([dynamic]LINE, context.temp_allocator)
	data.polyline = mem.make_non_zeroed([dynamic]POLYLINE, context.temp_allocator)
	data.polygon = mem.make_non_zeroed([dynamic]POLYGON, context.temp_allocator)
	data.shape_ptrs = mem.make_non_zeroed([dynamic]svg_shape_ptr, context.temp_allocator)
	defer {
		delete(data.path)
		delete(data.rect)
		delete(data.circle)
		delete(data.ellipse)
		delete(data.line)
		delete(data.polyline)
		delete(data.polygon)
		delete(data.shape_ptrs)
	}
	_parse_svg_element(xml_doc, 0, &data, arena)

	parser.svg = data.svg
	if len(data.path) > 0 {
		parser.path = mem.make_non_zeroed([]PATH, len(data.path), arena)
		mem.copy_non_overlapping(&parser.path[0], &data.path[0], len(data.path) * size_of(PATH))
	}
	if len(data.rect) > 0 {
		parser.rect = mem.make_non_zeroed([]RECT, len(data.rect), arena)
		mem.copy_non_overlapping(&parser.rect[0], &data.rect[0], len(data.rect) * size_of(RECT))
	}
	if len(data.circle) > 0 {
		parser.circle = mem.make_non_zeroed([]CIRCLE, len(data.circle), arena)
		mem.copy_non_overlapping(&parser.circle[0], &data.circle[0], len(data.circle) * size_of(CIRCLE))
	}
	if len(data.ellipse) > 0 {
		parser.ellipse = mem.make_non_zeroed([]ELLIPSE, len(data.ellipse), arena)
		mem.copy_non_overlapping(&parser.ellipse[0], &data.ellipse[0], len(data.ellipse) * size_of(ELLIPSE))
	}
	if len(data.line) > 0 {
		parser.line = mem.make_non_zeroed([]LINE, len(data.line), arena)
		mem.copy_non_overlapping(&parser.line[0], &data.line[0], len(data.line) * size_of(LINE))
	}
	if len(data.polyline) > 0 {
		parser.polyline = mem.make_non_zeroed([]POLYLINE, len(data.polyline), arena)
		mem.copy_non_overlapping(&parser.polyline[0], &data.polyline[0], len(data.polyline) * size_of(POLYLINE))
	}
	if len(data.polygon) > 0 {
		parser.polygon = mem.make_non_zeroed([]POLYGON, len(data.polygon), arena)
		mem.copy_non_overlapping(&parser.polygon[0], &data.polygon[0], len(data.polygon) * size_of(POLYGON))
	}
	if len(data.shape_ptrs) > 0 {
		parser.shape_ptrs = mem.make_non_zeroed([]svg_shape_ptr, len(data.shape_ptrs), arena)
		mem.copy_non_overlapping(&parser.shape_ptrs[0], &data.shape_ptrs[0], len(data.shape_ptrs) * size_of(svg_shape_ptr))
	}
	shapes_ : __shapes = {
		polys = mem.make_non_zeroed([dynamic]linalg.PointF, context.temp_allocator),
		n_polys = mem.make_non_zeroed([dynamic]u32, context.temp_allocator),
		n_types = mem.make_non_zeroed([dynamic]u32, context.temp_allocator),
		types = mem.make_non_zeroed([dynamic]geometry.curve_type, context.temp_allocator),
		colors = mem.make_non_zeroed([dynamic]linalg.Point3DwF, context.temp_allocator),
		strokeColors = mem.make_non_zeroed([dynamic]linalg.Point3DwF, context.temp_allocator),
		thickness = mem.make_non_zeroed([dynamic]f32, context.temp_allocator),
	}
	defer {
		delete(shapes_.polys)
		delete(shapes_.n_polys)
		delete(shapes_.n_types)
		delete(shapes_.types)
		delete(shapes_.colors)
		delete(shapes_.strokeColors)
		delete(shapes_.thickness)
	}
	for s in parser.shape_ptrs {
		#partial switch v in s {
		case ^PATH: _parse_path(&shapes_, v, arena) or_return
		case ^RECT: _parse_rect(&shapes_, v, arena) or_return
		case ^CIRCLE: _parse_circle(&shapes_, v, arena) or_return
		case ^ELLIPSE: _parse_ellipse(&shapes_, v, arena) or_return
		case ^LINE: _parse_line(&shapes_, v, arena) or_return
		case ^POLYLINE: _parse_polyline(&shapes_, v, arena) or_return
		case ^POLYGON: _parse_polygon(&shapes_, v, arena) or_return
		}
	}
	// 새로운 구조로 변환
	if len(shapes_.n_polys) == 0 {
		parser.shapes = geometry.shapes{nodes = nil}
		return parser, nil
	}
	
	nodes := mem.make_non_zeroed([dynamic]geometry.shape_node, context.temp_allocator)
	defer delete(nodes)
	
	start_poly :u32 = 0
	start_type :u32 = 0
	
	for i in 0..<len(shapes_.n_polys) {
		n_poly := shapes_.n_polys[i]
		n_type := shapes_.n_types[i]
		
		if n_poly == 0 do continue
		
		// 색상과 스트로크 정보 가져오기
		color := shapes_.colors[i] if i < len(shapes_.colors) else linalg.Point3DwF{0, 0, 0, 0}
		stroke_color := shapes_.strokeColors[i] if i < len(shapes_.strokeColors) else linalg.Point3DwF{0, 0, 0, 0}
		thickness := shapes_.thickness[i] if i < len(shapes_.thickness) else 0.0
		
		// 선분들 생성
		lines := mem.make_non_zeroed([dynamic]geometry.shape_line, context.temp_allocator)
		defer delete(lines)
		
		poly_idx :u32 = 0
		type_idx :u32 = 0
		
		for poly_idx < n_poly && type_idx < n_type {
			curve_type := shapes_.types[start_type + type_idx]
			
			if curve_type == .Line {
				start_point := shapes_.polys[start_poly + poly_idx]
				end_point := shapes_.polys[start_poly + (poly_idx + 1) % n_poly]
				non_zero_append(&lines, geometry.shape_line{
					start = start_point,
					control0 = {0, 0},
					control1 = {0, 0},
					end = end_point,
					type = .Line,
				})
				poly_idx += 1
				type_idx += 1
			} else if curve_type == .Quadratic {
				start_point := shapes_.polys[start_poly + poly_idx]
				control_point := shapes_.polys[start_poly + poly_idx + 1]
				end_point := shapes_.polys[start_poly + (poly_idx + 2) % n_poly]
				non_zero_append(&lines, geometry.shape_line{
					start = start_point,
					control0 = control_point,
					control1 = {0, 0},
					end = end_point,
					type = .Quadratic,
				})
				poly_idx += 2
				type_idx += 1
			} else {
				start_point := shapes_.polys[start_poly + poly_idx]
				control0 := shapes_.polys[start_poly + poly_idx + 1]
				control1 := shapes_.polys[start_poly + poly_idx + 2]
				end_point := shapes_.polys[start_poly + (poly_idx + 3) % n_poly]
				non_zero_append(&lines, geometry.shape_line{
					start = start_point,
					control0 = control0,
					control1 = control1,
					end = end_point,
					type = .Unknown,
				})
				poly_idx += 3
				type_idx += 1
			}
		}
		
		if len(lines) > 0 {
			lines_array := mem.make_non_zeroed([]geometry.shape_line, len(lines), arena)
			mem.copy_non_overlapping(&lines_array[0], &lines[0], len(lines) * size_of(geometry.shape_line))
			
			n_polygons := mem.make_non_zeroed([]u32, 1, arena)
			n_polygons[0] = n_poly
			
			non_zero_append(&nodes, geometry.shape_node{
				lines = lines_array,
				color = color,
				stroke_color = stroke_color,
				thickness = thickness,
			})
		}
		
		start_poly += n_poly
		start_type += n_type
	}
	
	if len(nodes) > 0 {
		nodes_array := mem.make_non_zeroed([]geometry.shape_node, len(nodes), arena)
		mem.copy_non_overlapping(&nodes_array[0], &nodes[0], len(nodes) * size_of(geometry.shape_node))
		parser.shapes = geometry.shapes{nodes = nodes_array}
	} else {
		parser.shapes = geometry.shapes{nodes = nil}
	}
	return parser, nil
}

//0 or 1 string to bool
@private _parse_bool :: proc "contextless" (str: string, i:^int) -> (bool, SVG_ERROR) {
	idn := strings.index_any(str[i^:], "01")
	if idn == -1 do return false, .INVALID_NODE
	i^ += idn

	ch := (transmute([]u8)str)[i^]
	if ch == '0' {
		i^ += 1
		return false, nil
	} else if ch == '1' {
		i^ += 1
		return true, nil
	}
	return false, .INVALID_NODE
}

@private _parse_path :: proc(shapes: ^__shapes, path: ^PATH, allocator: mem.Allocator) -> SVG_ERROR {
	_read_path_p :: proc (str: string, idx: ^int, op: u8, cur: linalg.PointF) -> (result: linalg.PointF, err: SVG_ERROR) {
		p := _parse_point(str, idx) or_return
		p[1] *= -1
		if unicode.is_lower(rune(op)) {
			p += cur
		}
		return p, nil
	}
	_read_path_fx :: proc (str: string, idx: ^int, op: u8, cur_x: f32) -> (result: f32, err: SVG_ERROR) {
		f, parse_ok := strconv.parse_f32(str[idx^:])
		if !parse_ok do return 0, .INVALID_NODE
		if unicode.is_lower(rune(op)) do f += cur_x
		return f, nil
	}
	_read_path_fy :: proc (str: string, idx: ^int, op: u8, cur_y: f32) -> (result: f32, err: SVG_ERROR) {
		f, parse_ok := strconv.parse_f32(str[idx^:])
		if !parse_ok do return 0, .INVALID_NODE
		f *= -1
		if unicode.is_lower(rune(op)) do f += cur_y
		return f, nil
	}
	//arc first point parameter is rx,ry
	_read_path_r :: proc (str: string, idx: ^int) -> (result: linalg.PointF, err: SVG_ERROR) {
		r := _parse_point(str, idx) or_return
		return r, nil
	}

	has_stroke := path._0.stroke != nil && path._0.stroke_width != nil && path._0.stroke_width.? > 0
	has_fill := path._0.fill != nil
	if !(path.d != nil && (has_fill || has_stroke)) do return nil// empty path


	g_line :: struct {
		start: linalg.PointF,
		control0: linalg.PointF,
		control1: linalg.PointF,
		end: linalg.PointF,
		type: geometry.curve_type,
	}
	g_line_init :: #force_inline proc "contextless" (start: linalg.PointF, end: linalg.PointF) -> g_line {
		return {start, {0, 0}, {0, 0}, end, .Line}
	}
	g_quadratic_init :: #force_inline proc "contextless" (start: linalg.PointF, control: linalg.PointF, end: linalg.PointF) -> g_line {
		return {start, control, 0, end, .Quadratic}
	}
	g_cubic_init :: #force_inline proc "contextless" (start: linalg.PointF, control0: linalg.PointF, control1: linalg.PointF, end: linalg.PointF) -> g_line {
		return {start, control0, control1, end, .Unknown}
	}
	compare :: #force_inline proc "contextless" (a: linalg.PointF, b: linalg.PointF) -> bool {
		return a[0] == b[0] && a[1] == b[1]
	}

	cur: linalg.PointF = {0, 0}
	start: bool = false
	line :g_line

	i: int = 0
	op_: Maybe(u8) = nil

	start_idx := 0
	for i in 0..<len(shapes.n_polys) {
		start_idx += int(shapes.n_polys[i])
	}
	start_type_idx := 0
	for i in 0..<len(shapes.n_types) {
		start_type_idx += int(shapes.n_types[i])
	}
	starti: int = start_idx
	start_typei := start_type_idx
	n_polys := 0
	n_types := 0
	color_len := 1


	append_line :: proc(polys: ^[dynamic]linalg.PointF, types: ^[dynamic]geometry.curve_type, n_polys: ^int, n_types: ^int, line: g_line) {
		if line.type == .Quadratic {
			n_polys^ += 1
			non_zero_append(polys, line.control0)
			non_zero_append_elem(types, geometry.curve_type.Quadratic)
		} else if line.type == .Unknown {
			n_polys^ += 2
			non_zero_append(polys, line.control0)
			non_zero_append(polys, line.control1)
			non_zero_append_elem(types, geometry.curve_type.Unknown)
		} else {
			non_zero_append_elem(types, geometry.curve_type.Line)
		}
		non_zero_append(polys, line.end)
		n_polys^ += 1
		n_types^ += 1
	}
	
	for i < len(path.d.?) {
		if path.d.?[i] == 'Z' || path.d.?[i] == 'z' {
			if len(shapes.polys) <= start_idx do return .INVALID_NODE
			if start {
				start = false
			}
			// if !compare(line.start, line.end) {
			// 	append_line(&shapes.polys, &shapes.types, &n_polys, &n_types, line)
			// }
			cur = shapes.polys[starti]
			i += 1
			op_ = nil
			continue
		}
		
		// Skip whitespace
		for i < len(path.d.?) {
			c := path.d.?[i]
			if c != ' ' && c != '\r' && c != '\n' && c != '\t' {
				break
			}
			i += 1
		}
		if i >= len(path.d.?) {
			break
		}
		
		if (path.d.?[i] >= 'A' && path.d.?[i] <= 'Z') || (path.d.?[i] >= 'a' && path.d.?[i] <= 'z') {
			op_ = path.d.?[i]
			i += 1
		}
		if i >= len(path.d.?) {
			break
		}
		
		prevS: Maybe(linalg.PointF) = nil
		prevT: Maybe(linalg.PointF) = nil

		if op_ == nil do return .INVALID_NODE
		
		switch op_.? {
		case 'M', 'm':
			p := _read_path_p(path.d.?, &i, op_.?, cur) or_return
			line.start = p
			cur = p
			starti = start_idx + n_polys
			if n_polys > 0 {
				non_zero_append(&shapes.n_polys, auto_cast n_polys)
				non_zero_append(&shapes.n_types, auto_cast n_types)
				start_idx += n_polys
				start_typei += n_types
				n_polys = 0
				n_types = 0
				color_len += 1
			}
			start = true
			prevS = nil
			prevT = nil
			continue
		case 'L', 'l':
			if !start do return .INVALID_NODE
			p := _read_path_p(path.d.?, &i, op_.?, cur) or_return
			line = g_line_init(line.start, p)
			cur = p
			prevS = nil
			prevT = nil
		case 'V', 'v':
			if !start do return .INVALID_NODE
			y := _read_path_fy(path.d.?, &i, op_.?, cur[1]) or_return
			line = g_line_init(line.start, linalg.PointF{line.start[0], y})
			cur[1] = y
			prevS = nil
			prevT = nil
		case 'H', 'h':
			if !start do return .INVALID_NODE
			x := _read_path_fx(path.d.?, &i, op_.?, cur[0]) or_return
			line = g_line_init(line.start, linalg.PointF{x, line.start[1]})
			cur[0] = x
			prevS = nil
			prevT = nil
		case 'Q', 'q':
			if !start do return .INVALID_NODE
			p := _read_path_p(path.d.?, &i, op_.?, cur) or_return
			p2 := _read_path_p(path.d.?, &i, op_.?, cur) or_return

			line = g_quadratic_init(line.start, p, p2)
			cur = p2
			prevS = nil
			prevT = p
		case 'C', 'c':
			if !start do return .INVALID_NODE
			p := _read_path_p(path.d.?, &i, op_.?, cur) or_return
			p2 := _read_path_p(path.d.?, &i, op_.?, cur) or_return
			p3 := _read_path_p(path.d.?, &i, op_.?, cur) or_return
			if compare(p, line.start) {
				line = g_quadratic_init(line.start, p2, p3)
			} else {
				line = g_cubic_init(line.start, p, p2, p3)
			}

			cur = p3
			prevS = p2
			prevT = nil
		case 'S', 's':
			if !start do return .INVALID_NODE
			if prevS == nil {
				p := _read_path_p(path.d.?, &i, op_.?, cur) or_return
				p2 := _read_path_p(path.d.?, &i, op_.?, cur) or_return
				line = g_quadratic_init(line.start, p, p2)
				cur = p2
				prevS = p
			} else {
				p := _read_path_p(path.d.?, &i, op_.?, cur) or_return
				p0 := linalg.xy_mirror_point(cur, prevS.?)
				p2 := _read_path_p(path.d.?, &i, op_.?, cur) or_return
				line = g_cubic_init(line.start, p0, p, p2)
				cur = p2
				prevS = p
			}
			prevT = nil
		case 'T', 't':
			if !start do return .INVALID_NODE
			p := _read_path_p(path.d.?, &i, op_.?, cur) or_return
			if prevT == nil {
				line = g_line_init(line.start, p)
			} else {
				p0 := linalg.xy_mirror_point(cur, prevT.?)
				line = g_quadratic_init(line.start, p0, p)
				cur = p
				prevT = p0
			}
			prevS = nil
		case 'A', 'a':
			if !start do return .INVALID_NODE
			prevS = nil
			prevT = nil

			doublePI: f32 = math.PI * 2

			r := _read_path_r(path.d.?, &i) or_return
			xx := _parse_number(path.d.?, &i) or_return
			x_angle: f32 = xx * doublePI / 360
			large_arc: bool = _parse_bool(path.d.?, &i) or_return
			sweep: bool = _parse_bool(path.d.?, &i) or_return
			end := _read_path_p(path.d.?, &i, op_.?, cur) or_return

			end[1] *= -1
			cur[1] *= -1

			sin_val := math.sin(x_angle)
			cos_val := math.cos(x_angle)

			pp := linalg.PointF{
				cos_val * (cur[0] - end[0]) / 2 + sin_val * (cur[1] - end[1]) / 2,
				-sin_val * (cur[0] - end[0]) / 2 + cos_val * (cur[1] - end[1]) / 2,
			}

			prevS = nil
			prevT = nil
			if (pp[0] == 0 && pp[1] == 0) || (r[0] == 0 || r[1] == 0) {
				end[1] *= -1
				line = g_line_init(line.start, end)
				cur = end
			} else {
				r = linalg.PointF{abs(r[0]), abs(r[1])}

				lambda := (pp[0] * pp[0]) / (r[0] * r[0]) + (pp[1] * pp[1]) / (r[1] * r[1])

				if lambda > 1 {
					sqrt_lambda := math.sqrt(lambda)
					r = linalg.PointF{r[0] * sqrt_lambda, r[1] * sqrt_lambda}
				}
				r_sq := linalg.PointF{r[0] * r[0], r[1] * r[1]}
				pp_sq := linalg.PointF{pp[0] * pp[0], pp[1] * pp[1]}

				radicant: f32 = r_sq[0] * r_sq[1] - r_sq[0] * pp_sq[1] - r_sq[1] * pp_sq[0]
				if radicant < 0 do radicant = 0
				radicant /= (r_sq[0] * pp_sq[1]) + (r_sq[1] * pp_sq[0])
				if large_arc == sweep {
					radicant = -math.sqrt(radicant)
				} else {
					radicant = math.sqrt(radicant)
				}

				centerp := linalg.PointF{
					radicant * r[0] / r[1] * pp[1],
					radicant * -r[1] / r[0] * pp[0],
				}
				center := linalg.PointF{
					cos_val * centerp[0] - sin_val * centerp[1] + (cur[0] + end[0]) / 2,
					sin_val * centerp[0] + cos_val * centerp[1] + (cur[1] + end[1]) / 2,
				}

				v1: linalg.PointF = linalg.PointF{(pp[0] - centerp[0]) / r[0], (pp[1] - centerp[1]) / r[1]}
				v2: linalg.PointF = linalg.PointF{(-pp[0] - centerp[0]) / r[0], (-pp[1] - centerp[1]) / r[1]}

				vector_angle :: proc(u: linalg.PointF, v: linalg.PointF) -> f32 {
					sign: f32 = 0 > linalg.vector_cross2(u, v) ? -1 : 1
					dot_ := linalg.dot(u, v)
					dot_ = math.clamp(dot_, -1, 1)

					return sign * math.acos(dot_)
				}
				map_to_ellipse :: proc(_in: linalg.PointF, _r: linalg.PointF, _cos: f32, _sin: f32, _center: linalg.PointF) -> linalg.PointF {
					__in := _in
					__in = linalg.PointF{__in[0] * _r[0], __in[1] * _r[1]}
					return linalg.PointF{
						_cos * __in[0] - _sin * __in[1],
						_sin * __in[0] + _cos * __in[1],
					} + _center
				}

				ang1 := vector_angle(linalg.PointF{1, 0}, v1)
				ang2 := vector_angle(v1, v2)

				if !sweep && ang2 > 0 {
					ang2 -= doublePI
				} else if sweep && ang2 < 0 {
					ang2 += doublePI
				}
				ratio: f32 = abs(ang2) / (doublePI / 4.0)
				if math.abs(1 - ratio) < math.F32_EPSILON do ratio = 1
				nseg: int = int(math.max(1, math.ceil(ratio)))

				ang2 /= f32(nseg)

				for j in 0..<nseg {
					_ = j
					a := ang2 == 1.57079625 ? 0.551915024494 : (ang2 == -1.57079625 ? -0.551915024494 : 4.0 / 3.0 * math.tan(ang2 / 4))
					xy1 := linalg.PointF{math.cos(ang1), math.sin(ang1)}
					xy2 := linalg.PointF{math.cos(ang1 + ang2), math.sin(ang1 + ang2)}
					ellipse_0 := map_to_ellipse(linalg.PointF{xy1[0] - xy1[1] * a, xy1[1] + xy1[0] * a}, r, cos_val, sin_val, center)
					ellipse_1 := map_to_ellipse(linalg.PointF{xy2[0] + xy2[1] * a, xy2[1] - xy2[0] * a}, r, cos_val, sin_val, center)
					ellipse_2 := map_to_ellipse(linalg.PointF{xy2[0], xy2[1]}, r, cos_val, sin_val, center)
					line = g_cubic_init(line.start, 
						linalg.PointF{ellipse_0[0], -ellipse_0[1]},
						 linalg.PointF{ellipse_1[0], -ellipse_1[1]},
						  linalg.PointF{ellipse_2[0], -ellipse_2[1]})
					append_line(&shapes.polys, &shapes.types, &n_polys, &n_types, line)
					line.start = line.end

					ang1 += ang2
				}

				cur = line.end
				continue
			}
			case: return .INVALID_NODE
		}
		
		if start {
			append_line(&shapes.polys, &shapes.types, &n_polys, &n_types, line)
			line.start = line.end
		}
	}	
	if len(shapes.polys) <= start_idx do return .INVALID_NODE

	non_zero_append(&shapes.n_polys, auto_cast n_polys)
	non_zero_append(&shapes.n_types, auto_cast n_types)

	non_zero_resize(&shapes.colors, len(shapes.colors) + color_len)
	non_zero_resize(&shapes.strokeColors, len(shapes.strokeColors) + color_len)
	non_zero_resize(&shapes.thickness, len(shapes.thickness) + color_len)

	color__ := has_fill ? _parse_color(path._0.fill.?, path._0.fill_opacity) or_return : linalg.Point3DwF{0, 0, 0, 0}
	stroke__ := has_stroke ? _parse_color(path._0.stroke.?, path._0.stroke_opacity) or_return : linalg.Point3DwF{0, 0, 0, 0}
	thickness__ := has_stroke ? path._0.stroke_width.? : 0
	for i in 0..<color_len {
		shapes.colors[len(shapes.colors) - color_len + i] = color__
		shapes.strokeColors[len(shapes.strokeColors) - color_len + i] = stroke__
		shapes.thickness[len(shapes.thickness) - color_len + i] = thickness__
	}

	return nil
}

@private _parse_rect :: proc(shapes: ^__shapes, rect: ^RECT, allocator: mem.Allocator) -> SVG_ERROR {
	return nil
}

@private _parse_circle :: proc(shapes: ^__shapes, circle: ^CIRCLE, allocator: mem.Allocator) -> SVG_ERROR {
	return nil
}

@private _parse_ellipse :: proc(shapes: ^__shapes, ellipse: ^ELLIPSE, allocator: mem.Allocator) -> SVG_ERROR {
	return nil
}

@private _parse_line :: proc(shapes: ^__shapes, line: ^LINE, allocator: mem.Allocator) -> SVG_ERROR {
	return nil
}

@private _parse_polyline :: proc(shapes: ^__shapes, polyline: ^POLYLINE, allocator: mem.Allocator) -> SVG_ERROR {
	return nil
}

@private _parse_polygon :: proc(shapes: ^__shapes, polygon: ^POLYGON, allocator: mem.Allocator) -> SVG_ERROR {
	return nil
}

@private _parse_number :: proc(str: string, i:^int) -> (f32, SVG_ERROR) {
	idn := strings.index_any(str[i^:], "0123456789.")
	if idn == -1 do return 0, .INVALID_NODE
	i^ += idn

	nonidx := i^ + 1
	for nonidx < len(str) {
		c := str[nonidx]
		if !(c >= '0' && c <= '9' || c == '.') {
			break
		}
		nonidx += 1
	}
	flen: int
	value, ok := strconv.parse_f32(str[i^:nonidx], &flen)
	if !ok do return 0, .INVALID_NODE

	i^ += flen
	return value, nil
}

@private _parse_color :: proc(color: string, opacity: Maybe(f32)) -> (result: linalg.Point3DwF, err: SVG_ERROR) {
	if color == "none" {
		return linalg.Point3DwF{0, 0, 0, 0}, nil
	}

	res: Maybe(u32)

	// Parse hex color
	if len(color) > 0 && color[0] == '#' {
		if len(color) == 4 {
			// #fff format
			hex_str := color[1:]
			hex_val, hex_ok := strconv.parse_u64_of_base(hex_str, 16)
			if !hex_ok {
				return linalg.Point3DwF{0, 0, 0, 0}, .INVALID_NODE
			}
			r := f32((hex_val >> 8) & 0xf) / 15.0
			g := f32((hex_val >> 4) & 0xf) / 15.0
			b := f32(hex_val & 0xf) / 15.0
			a := f32(0xf) / 15.0
			if opacity, ok := opacity.?; ok {
				a = opacity
			}
			return linalg.Vector4f32{r, g, b, a}, nil
		} else if len(color) == 7 {
			// #ffffff format
			hex_str := color[1:]
			hex_val, hex_ok := strconv.parse_u64_of_base(hex_str, 16)
			if !hex_ok {
				return linalg.Point3DwF{0, 0, 0, 0}, .INVALID_NODE
			}
			r := f32((hex_val >> 16) & 0xff) / 255.0
			g := f32((hex_val >> 8) & 0xff) / 255.0
			b := f32(hex_val & 0xff) / 255.0
			a := f32(0xff) / 255.0
			if opacity, ok := opacity.?; ok {
				a = opacity
			}
			return linalg.Vector4f32{r, g, b, a}, nil
		}
	} else if len(color) >= 3 && color[:3] == "rgb" {
		// TODO: rgb/rgba format
		return linalg.Point3DwF{0, 0, 0, 0}, .UNSUPPORTED_FEATURE
	} else if len(color) >= 3 && color[:3] == "hsl" {
		// TODO: hsl/hsla format
		return linalg.Point3DwF{0, 0, 0, 0}, .UNSUPPORTED_FEATURE
	}

	// Try to find CSS color name
	color_lower := strings.to_lower(color, context.temp_allocator)
	for name in CSS_COLOR {
		name_str := fmt.tprintf("%v", name)
		if strings.to_lower(name_str, context.temp_allocator) == color_lower {
			res = u32(name)
			break
		}
	}

	if res_val, ok := res.?; ok {
		r := f32((res_val >> 16) & 0xff) / 255.0
		g := f32((res_val >> 8) & 0xff) / 255.0
		b := f32(res_val & 0xff) / 255.0
		a := f32(0xff) / 255.0
		if opacity, ok := opacity.?; ok {
			a = opacity
		}
		return linalg.Vector4f32{r, g, b, a}, nil
	}

	return linalg.Point3DwF{0, 0, 0, 0}, .INVALID_NODE
}