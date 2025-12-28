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

SVG :: struct {
	width:  Maybe(string),
	height: Maybe(string),
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
	points: Maybe([]linalg.PointF),
	_0:     FILL_AND_STROKE,
}

POLYGON :: struct {
	points: Maybe([]linalg.PointF),
	_0:     FILL_AND_STROKE,
}

SVG_ERROR :: enum {
	NOT_INITIALIZED,
	OVERLAPPING_NODE,
	INVALID_NODE,
	UNSUPPORTED_FEATURE,
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

SVG_Parser :: struct {
	arena_allocator: Maybe(mem.Allocator),
    __arena:         mem.Dynamic_Arena,
	xml_error_code:  xml.Error,
	svg:             SVG,
	path:            []PATH,
	rect:            []RECT,
	circle:          []CIRCLE,
	ellipse:         []ELLIPSE,
	line:            []LINE,
	polyline:        []POLYLINE,
	polygon:         []POLYGON,
	shape_ptrs:      []svg_shape_ptr,
}

@private _parse_point :: proc(_str: string, i: ^int) -> (point: linalg.PointF, ok: bool) {
	// Find first digit or minus sign
	start := i^
	for start < len(_str) && !strings.is_digit(_str[start]) && _str[start] != '-' && _str[start] != '.' {
		start += 1
	}
	if start >= len(_str) {
		return {}, false
	}

	// Find end of first number
	end := start + 1
	found_dot := false
	for end < len(_str) {
		c := _str[end]
		if strings.is_digit(c) {
			end += 1
		} else if c == '.' {
			if found_dot {
				break
			}
			found_dot = true
			end += 1
		} else if c == '-' && end > start {
			break
		} else {
			break
		}
	}

	// Parse x
	x_str := _str[start:end]
	x, x_ok := strconv.parse_f32(x_str)
	if !x_ok {
		return {}, false
	}

	// Find start of second number
	start = end
	for start < len(_str) && !strings.is_digit(_str[start]) && _str[start] != '-' && _str[start] != '.' {
		start += 1
	}
	if start >= len(_str) {
		return {}, false
	}

	// Find end of second number
	end = start + 1
	found_dot = false
	for end < len(_str) {
		c := _str[end]
		if strings.is_digit(c) {
			end += 1
		} else if c == '.' {
			if found_dot {
				break
			}
			found_dot = true
			end += 1
		} else if c == '-' && end > start {
			break
		} else {
			break
		}
	}

	// Parse y
	y_str := _str[start:end]
	y, y_ok := strconv.parse_f32(y_str)
	if !y_ok {
		return {}, false
	}

	i^ = end
	return linalg.PointF{x, y}, true
}

@private _parse_number :: proc($T: typeid, _str: string, i: ^int) -> (value: T, ok: bool) where intrinsics.type_is_numeric(T) {
	start := i^
	for start < len(_str) && !strings.is_digit(_str[start]) && _str[start] != '-' && _str[start] != '.' {
		start += 1
	}
	if start >= len(_str) {
		return {}, false
	}

	end := start + 1
	found_dot := false
	for end < len(_str) {
		c := _str[end]
		if strings.is_digit(c) {
			end += 1
		} else if c == '.' {
			if found_dot {
				break
			}
			found_dot = true
			end += 1
		} else if c == '-' && end > start {
			break
		} else {
			break
		}
	}

	num_str := _str[start:end]
	when intrinsics.type_is_float(T) {
		value, ok = strconv.parse_f32(num_str)
	} else when intrinsics.type_is_integer(T) {
		value, ok = strconv.parse_int(T, num_str)
	} else {
		return {}, false
	}

	i^ = end
	return value, ok
}

@private _parse_bool :: proc(_str: string, i: ^int) -> (value: bool, ok: bool) {
	start := i^
	for start < len(_str) && _str[start] != '0' && _str[start] != '1' {
		start += 1
	}
	if start >= len(_str) {
		return false, false
	}

	value = _str[start] == '1'
	i^ = start + 1
	return value, true
}

@private _parse_points :: proc(_str: string, allocator: mem.Allocator) -> (points: []linalg.PointF, ok: bool) {
	points_list := make([dynamic]linalg.PointF, 0, 16, allocator)
	defer if !ok {
		delete(points_list)
	}

	i := 0
	for i < len(_str) {
		point, point_ok := _parse_point(_str, &i)
		if !point_ok {
			ok = false
			return
		}
		append(&points_list, point)
	}

	ok = true
	return points_list[:], true
}

@private _parse_xml_element :: proc(out: svg_shape_ptr, doc: ^xml.Document, element: xml.Element_ID, allocator: mem.Allocator) -> (ok: bool) {
	element_data := &doc.elements[element]
	
	// Iterate through attributes
	for attr in element_data.attribs {
		field_name := attr.key
		value := attr.val

		// Try to find matching field in struct
		#partial switch v in out {
		case ^PATH:
			switch field_name {
			case "d":
				v.d = value
			case "fill-rule":
				v.fill_rule = value
			case "clip-rule":
				v.clip_rule = value
			case "fill":
				v._0.fill = value
			case "stroke":
				v._0.stroke = value
			case "stroke-width":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v._0.stroke_width = f
				}
			case "fill-opacity":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v._0.fill_opacity = f
				}
			case "stroke-opacity":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v._0.stroke_opacity = f
				}
			}
		case ^RECT:
			switch field_name {
			case "x":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v.x = f
				}
			case "y":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v.y = f
				}
			case "width":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v.width = f
				}
			case "height":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v.height = f
				}
			case "rx":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v.rx = f
				}
			case "ry":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v.ry = f
				}
			case "fill":
				v._0.fill = value
			case "stroke":
				v._0.stroke = value
			case "stroke-width":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v._0.stroke_width = f
				}
			case "fill-opacity":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v._0.fill_opacity = f
				}
			case "stroke-opacity":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v._0.stroke_opacity = f
				}
			}
		case ^CIRCLE:
			switch field_name {
			case "cx":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v.cx = f
				}
			case "cy":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v.cy = f
				}
			case "r":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v.r = f
				}
			case "fill":
				v._0.fill = value
			case "stroke":
				v._0.stroke = value
			case "stroke-width":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v._0.stroke_width = f
				}
			case "fill-opacity":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v._0.fill_opacity = f
				}
			case "stroke-opacity":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v._0.stroke_opacity = f
				}
			}
		case ^ELLIPSE:
			switch field_name {
			case "cx":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v.cx = f
				}
			case "cy":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v.cy = f
				}
			case "rx":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v.rx = f
				}
			case "ry":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v.ry = f
				}
			case "fill":
				v._0.fill = value
			case "stroke":
				v._0.stroke = value
			case "stroke-width":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v._0.stroke_width = f
				}
			case "fill-opacity":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v._0.fill_opacity = f
				}
			case "stroke-opacity":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v._0.stroke_opacity = f
				}
			}
		case ^LINE:
			switch field_name {
			case "x1":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v.x1 = f
				}
			case "y1":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v.y1 = f
				}
			case "x2":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v.x2 = f
				}
			case "y2":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v.y2 = f
				}
			case "fill":
				v._0.fill = value
			case "stroke":
				v._0.stroke = value
			case "stroke-width":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v._0.stroke_width = f
				}
			case "fill-opacity":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v._0.fill_opacity = f
				}
			case "stroke-opacity":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v._0.stroke_opacity = f
				}
			}
		case ^POLYLINE:
			switch field_name {
			case "points":
				if pts, pts_ok := _parse_points(value, allocator); pts_ok {
					v.points = pts
				}
			case "fill":
				v._0.fill = value
			case "stroke":
				v._0.stroke = value
			case "stroke-width":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v._0.stroke_width = f
				}
			case "fill-opacity":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v._0.fill_opacity = f
				}
			case "stroke-opacity":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v._0.stroke_opacity = f
				}
			}
		case ^POLYGON:
			switch field_name {
			case "points":
				if pts, pts_ok := _parse_points(value, allocator); pts_ok {
					v.points = pts
				}
			case "fill":
				v._0.fill = value
			case "stroke":
				v._0.stroke = value
			case "stroke-width":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v._0.stroke_width = f
				}
			case "fill-opacity":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v._0.fill_opacity = f
				}
			case "stroke-opacity":
				if f, f_ok := strconv.parse_f32(value); f_ok {
					v._0.stroke_opacity = f
				}
			}
		case ^SVG:
			switch field_name {
			case "width":
				v.width = value
			case "height":
				v.height = value
			}
		}
	}

	return true
}

deinit :: proc(self: ^SVG_Parser) {
	if arena, ok := self.arena_allocator.?; ok {
		mem.dynamic_arena_destroy(&self.__arena)
		self.arena_allocator = nil
	}
}

init_parse :: proc(svg_data: []u8, allocator: mem.Allocator = context.allocator) -> (parser: SVG_Parser, err: SVG_ERROR) {
	parser = {}
    mem.dynamic_arena_init(&parser.__arena, allocator,allocator)
	arena := mem.dynamic_arena_allocator(&parser.__arena)
	parser.arena_allocator = arena
	defer if err != nil {
		deinit(&parser)
	}

	// Parse XML document
	xml_doc, xml_err := xml.parse_bytes(svg_data, {}, "", allocator = arena)
	if xml_err != nil {
		parser.xml_error_code = xml_err
		return parser, .INVALID_NODE
	}
	defer xml.destroy(xml_doc)

	// Initialize lists
	path_list := make([dynamic]PATH, 0, 16, arena)
	rect_list := make([dynamic]RECT, 0, 16, arena)
	circle_list := make([dynamic]CIRCLE, 0, 16, arena)
	ellipse_list := make([dynamic]ELLIPSE, 0, 16, arena)
	line_list := make([dynamic]LINE, 0, 16, arena)
	polyline_list := make([dynamic]POLYLINE, 0, 16, arena)
	polygon_list := make([dynamic]POLYGON, 0, 16, arena)
	shapes_list := make([dynamic]svg_shape_ptr, 0, 32, arena)

	// Process elements
	_process_element :: proc(
		doc: ^xml.Document,
		element_id: xml.Element_ID,
		path_list: ^[dynamic]PATH,
		rect_list: ^[dynamic]RECT,
		circle_list: ^[dynamic]CIRCLE,
		ellipse_list: ^[dynamic]ELLIPSE,
		line_list: ^[dynamic]LINE,
		polyline_list: ^[dynamic]POLYLINE,
		polygon_list: ^[dynamic]POLYGON,
		shapes_list: ^[dynamic]svg_shape_ptr,
		parser: ^SVG_Parser,
		allocator: mem.Allocator,
	) -> (ok: bool) {
		element := &doc.elements[element_id]
		tag := element.ident

		switch tag {
		case "svg":
			_parse_xml_element(&parser.svg, doc, element_id, allocator)
		case "path":
			path := PATH{}
			if _parse_xml_element(&path, doc, element_id, allocator) {
				append(path_list, path)
				path_ptr := &path_list[len(path_list) - 1]
				append(shapes_list, path_ptr)
			}
		case "rect":
			rect := RECT{}
			if _parse_xml_element(&rect, doc, element_id, allocator) {
				append(rect_list, rect)
				rect_ptr := &rect_list[len(rect_list) - 1]
				append(shapes_list, rect_ptr)
			}
		case "circle":
			circle := CIRCLE{}
			if _parse_xml_element(&circle, doc, element_id, allocator) {
				append(circle_list, circle)
				circle_ptr := &circle_list[len(circle_list) - 1]
				append(shapes_list, circle_ptr)
			}
		case "ellipse":
			ellipse := ELLIPSE{}
			if _parse_xml_element(&ellipse, doc, element_id, allocator) {
				append(ellipse_list, ellipse)
				ellipse_ptr := &ellipse_list[len(ellipse_list) - 1]
				append(shapes_list, ellipse_ptr)
			}
		case "line":
			line := LINE{}
			if _parse_xml_element(&line, doc, element_id, allocator) {
				append(line_list, line)
				line_ptr := &line_list[len(line_list) - 1]
				append(shapes_list, line_ptr)
			}
		case "polyline":
			polyline := POLYLINE{}
			if _parse_xml_element(&polyline, doc, element_id, allocator) {
				append(polyline_list, polyline)
				polyline_ptr := &polyline_list[len(polyline_list) - 1]
				append(shapes_list, polyline_ptr)
			}
		case "polygon":
			polygon := POLYGON{}
			if _parse_xml_element(&polygon, doc, element_id, allocator) {
				append(polygon_list, polygon)
				polygon_ptr := &polygon_list[len(polygon_list) - 1]
				append(shapes_list, polygon_ptr)
			}
		}

		// Process child elements
		for value in element.value {
			#partial switch v in value {
			case xml.Element_ID:
				_process_element(
					doc, v, path_list, rect_list, circle_list,
					ellipse_list, line_list, polyline_list, polygon_list,
					shapes_list, parser, allocator,
				)
			}
		}

		return true
	}

	// Process root element
	if xml_doc.element_count > 0 {
		_process_element(
			xml_doc, 0, &path_list, &rect_list, &circle_list,
			&ellipse_list, &line_list, &polyline_list, &polygon_list,
			&shapes_list, &parser, arena,
		)
	}

	// Copy to parser
	parser.path = path_list[:]
	parser.rect = rect_list[:]
	parser.circle = circle_list[:]
	parser.ellipse = ellipse_list[:]
	parser.line = line_list[:]
	parser.polyline = polyline_list[:]
	parser.polygon = polygon_list[:]
	parser.shape_ptrs = shapes_list[:]

	return parser, nil
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

