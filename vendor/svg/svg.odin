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
import "base:intrinsics"
import "vendor:engine/geometry"

SVG :: struct {
	width:  string,
	height: string,
}

//! css not supported yet
FILL_AND_STROKE :: struct {
	fill:           string,
	stroke:         string,
	stroke_width:   Maybe(f32),
	//! Not supported yet
	stroke_linecap: string,
	//! Not supported yet
	stroke_dasharray: string,
	fill_opacity:   Maybe(f32),
	stroke_opacity: Maybe(f32),
}

PATH :: struct {
	d:         string,
	fill_rule: string,
	clip_rule: string,
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
	shapes:          Maybe(geometry.shapes),
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
	shapes:          Maybe(geometry.shapes),
}

deinit :: proc(self: ^svg_parser) {
	if arena, ok := self.arena_allocator.?; ok {
		mem.dynamic_arena_destroy(&self.__arena)
		self.arena_allocator = nil
	}
}

@private _parse_fill_and_stroke :: proc "contextless" (attribs: xml.Attribute, out: ^FILL_AND_STROKE) -> SVG_ERROR {
	err : bool = false
	
	switch attribs.key {
	case "fill":out.fill = attribs.val
	case "stroke":out.stroke = attribs.val
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
		for idx in inout_idx..<len(points) {
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
	if nonidx == inout_idx^ + 1 {
		err = .INVALID_NODE
		return
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
	if nonidx == len(points) {
		nonidx = len(points)
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
			case "width" : out.svg.width = a.val
			case "height" : out.svg.height = a.val
			}
		}
	case "path":
		non_zero_append(&out.path, PATH{})
		for a in e.attribs {
			switch a.key {
			case "d" : out.path[len(out.path) - 1].d = a.val
			case "fill-rule" : out.path[len(out.path) - 1].fill_rule = a.val
			case "clip-rule" : out.path[len(out.path) - 1].clip_rule = a.val
			case : _parse_fill_and_stroke(a, &out.path[len(out.path) - 1]._0) or_return
			}
		}
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
			case : _parse_fill_and_stroke(a, &out.rect[len(out.rect) - 1]._0) or_return
			}
		}
	case "circle":
		non_zero_append(&out.circle, CIRCLE{})
		for a in e.attribs {
			switch a.key {
			case "cx" : out.circle[len(out.circle) - 1].cx, err = strconv.parse_f32(a.val)
			case "cy" : out.circle[len(out.circle) - 1].cy, err = strconv.parse_f32(a.val)
			case "r" : out.circle[len(out.circle) - 1].r, err = strconv.parse_f32(a.val)
			case : _parse_fill_and_stroke(a, &out.circle[len(out.circle) - 1]._0) or_return
			}
		}
	case "ellipse":
		non_zero_append(&out.ellipse, ELLIPSE{})
		for a in e.attribs {
			switch a.key {
			case "cx" : out.ellipse[len(out.ellipse) - 1].cx, err = strconv.parse_f32(a.val)
			case "cy" : out.ellipse[len(out.ellipse) - 1].cy, err = strconv.parse_f32(a.val)
			case "rx" : out.ellipse[len(out.ellipse) - 1].rx, err = strconv.parse_f32(a.val)
			case "ry" : out.ellipse[len(out.ellipse) - 1].ry, err = strconv.parse_f32(a.val)
			case : _parse_fill_and_stroke(a, &out.ellipse[len(out.ellipse) - 1]._0) or_return
			}
		}
	case "line":
		non_zero_append(&out.line, LINE{})
		for a in e.attribs {
			switch a.key {
			case "x1" : out.line[len(out.line) - 1].x1, err = strconv.parse_f32(a.val)
			case "y1" : out.line[len(out.line) - 1].y1, err = strconv.parse_f32(a.val)
			case "x2" : out.line[len(out.line) - 1].x2, err = strconv.parse_f32(a.val)
			case "y2" : out.line[len(out.line) - 1].y2, err = strconv.parse_f32(a.val)
			case : _parse_fill_and_stroke(a, &out.line[len(out.line) - 1]._0) or_return
			}
		}
	case "polyline":
		non_zero_append(&out.polyline, POLYLINE{})
		for a in e.attribs {
			switch a.key {
			case "points" : out.polyline[len(out.polyline) - 1].points = _parse_points(a.val, allocator) or_return
			case : _parse_fill_and_stroke(a, &out.polyline[len(out.polyline) - 1]._0) or_return
			}
		}
		
	case "polygon":
		non_zero_append(&out.polygon, POLYGON{})
		for a in e.attribs {
			switch a.key {
			case "points" : out.polygon[len(out.polygon) - 1].points = _parse_points(a.val, allocator) or_return
			case : _parse_fill_and_stroke(a, &out.polygon[len(out.polygon) - 1]._0) or_return
			}
		}
	}
	if err do return .INVALID_NODE

	switch v in e.value[idx] {
	case xml.Element_ID:
		_parse_svg_element(xml_doc, v, out, allocator)
	case string:
		return nil//!svg xml not have value
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
	xml_doc, xml_err := xml.parse(svg_data, allocator = arena)
	if xml_err != nil {
		err = xml_err
		return
	}
	defer xml.destroy(xml_doc)

	data : __svg_parser_data = {}
	_parse_svg_element(xml_doc, 0, &data, allocator)

	return parser, nil
}

@private _parse_color :: proc(color: string, opacity: Maybe(f32)) -> (result: Maybe(linalg.Vector4f32), err: SVG_ERROR) {
	if color == "none" {
		return nil, nil
	}

	res: Maybe(u32)

	// Parse hex color
	if len(color) > 0 && color[0] == '#' {
		if len(color) == 4 {
			// #fff format
			hex_str := color[1:]
			hex_val, hex_ok := strconv.parse_u64_of_base(hex_str, 16)
			if !hex_ok {
				return nil, .INVALID_NODE
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
				return nil, .INVALID_NODE
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
		return nil, .UNSUPPORTED_FEATURE
	} else if len(color) >= 3 && color[:3] == "hsl" {
		// TODO: hsl/hsla format
		return nil, .UNSUPPORTED_FEATURE
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

	return nil, .INVALID_NODE
}