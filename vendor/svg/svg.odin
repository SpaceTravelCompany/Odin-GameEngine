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

deinit :: proc(self: ^svg_parser) {
	if arena, ok := self.arena_allocator.?; ok {
		mem.dynamic_arena_destroy(&self.__arena)
		self.arena_allocator = nil
	}
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
	xml_doc, xml_err := xml.parse_bytes(svg_data, {}, "", allocator = arena)
	if xml_err != nil {
		err = xml_err
		return
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
		parser: ^svg_parser,
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

	// Create shapes from parsed SVG elements
	poly_list := make([dynamic]linalg.PointF, 0, 64, arena)
	npolys_list := make([dynamic]u32, 0, 16, arena)
	ntypes_list := make([dynamic]u32, 0, 16, arena)
	types_list := make([dynamic]geometry.curve_type, 0, 64, arena)
	colors_list := make([dynamic]linalg.Point3DwF, 0, 16, arena)
	stroke_colors_list := make([dynamic]linalg.Point3DwF, 0, 16, arena)
	thickness_list := make([dynamic]f32, 0, 16, arena)

	shapes_result := geometry.shapes{
		poly = poly_list[:],
		nPolys = npolys_list[:],
		nTypes = ntypes_list[:],
		types = types_list[:],
		colors = colors_list[:],
		strokeColors = stroke_colors_list[:],
		thickness = thickness_list[:],
	}

	// Process all shapes
	for shape_ptr in shapes_list {
		switch v in shape_ptr {
		case ^PATH:
			if parse_err := _parse_path_to_shapes(&poly_list, &npolys_list, &ntypes_list, &types_list, &colors_list, &stroke_colors_list, &thickness_list, v^, arena); parse_err != nil {
				err = parse_err
				return
			}
		case ^RECT:
			if parse_err := _parse_rect_to_shapes(&poly_list, &npolys_list, &ntypes_list, &types_list, &colors_list, &stroke_colors_list, &thickness_list, v^, arena); parse_err != nil {
				err = parse_err
				return
			}
		case ^CIRCLE:
			if parse_err := _parse_circle_to_shapes(&poly_list, &npolys_list, &ntypes_list, &types_list, &colors_list, &stroke_colors_list, &thickness_list, v^, arena); parse_err != nil {
				err = parse_err
				return
			}
		case ^ELLIPSE:
			if parse_err := _parse_ellipse_to_shapes(&poly_list, &npolys_list, &ntypes_list, &types_list, &colors_list, &stroke_colors_list, &thickness_list, v^, arena); parse_err != nil {
				err = parse_err
				return
			}
		case ^LINE:
			if parse_err := _parse_line_to_shapes(&poly_list, &npolys_list, &ntypes_list, &types_list, &colors_list, &stroke_colors_list, &thickness_list, v^, arena); parse_err != nil {
				err = parse_err
				return
			}
		case ^POLYLINE:
			if parse_err := _parse_polyline_to_shapes(&poly_list, &npolys_list, &ntypes_list, &types_list, &colors_list, &stroke_colors_list, &thickness_list, v^, arena); parse_err != nil {
				err = parse_err
				return
			}
		case ^POLYGON:
			if parse_err := _parse_polygon_to_shapes(&poly_list, &npolys_list, &ntypes_list, &types_list, &colors_list, &stroke_colors_list, &thickness_list, v^, arena); parse_err != nil {
				err = parse_err
				return
			}
		case ^SVG:
			// SVG element itself doesn't create shapes
		}
	}

	shapes_result.poly = poly_list[:]
	shapes_result.nPolys = npolys_list[:]
	shapes_result.nTypes = ntypes_list[:]
	shapes_result.types = types_list[:]
	shapes_result.colors = colors_list[:]
	shapes_result.strokeColors = stroke_colors_list[:]
	shapes_result.thickness = thickness_list[:]

	parser.shapes = shapes_result

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

// Helper function to convert Vector4f32 to Point3DwF
@private _vec4_to_point3dw :: proc(v: linalg.Vector4f32) -> linalg.Point3DwF {
	return linalg.Point3DwF{v.x, v.y, v.z, v.w}
}

// Helper function to create rectangle points
@private _rect_to_points :: proc(x, y, width, height: f32) -> [4]linalg.PointF {
	return {
		linalg.PointF{x, -y},
		linalg.PointF{x + width, -y},
		linalg.PointF{x + width, -y - height},
		linalg.PointF{x, -y - height},
	}
}

// Helper function to create circle/ellipse points (approximated as cubic bezier)
@private _circle_to_points :: proc(center: linalg.PointF, radius: f32) -> [4]linalg.PointF {
	// Approximate circle with cubic bezier (4 control points)
	// Using magic number 0.551915024494 for circle approximation
	k := 0.551915024494 * radius
	return {
		linalg.PointF{center.x + radius, center.y},
		linalg.PointF{center.x + radius, center.y + k},
		linalg.PointF{center.x + radius, center.y - k},
		linalg.PointF{center.x, center.y - radius},
	}
}

@private _ellipse_to_points :: proc(center: linalg.PointF, rx, ry: f32) -> [4]linalg.PointF {
	// Approximate ellipse with cubic bezier
	k_x := 0.551915024494 * rx
	k_y := 0.551915024494 * ry
	return {
		linalg.PointF{center.x + rx, center.y},
		linalg.PointF{center.x + rx, center.y + k_y},
		linalg.PointF{center.x + rx, center.y - k_y},
		linalg.PointF{center.x, center.y - ry},
	}
}

@private _parse_rect_to_shapes :: proc(
	poly_list: ^[dynamic]linalg.PointF,
	npolys_list: ^[dynamic]u32,
	ntypes_list: ^[dynamic]u32,
	types_list: ^[dynamic]geometry.curve_type,
	colors_list: ^[dynamic]linalg.Point3DwF,
	stroke_colors_list: ^[dynamic]linalg.Point3DwF,
	thickness_list: ^[dynamic]f32,
	rect: RECT,
	allocator: mem.Allocator,
) -> (err: SVG_ERROR) {
	has_stroke := rect._0.stroke != nil && rect._0.stroke_width != nil && rect._0.stroke_width.? > 0
	has_fill := rect._0.fill != nil
	if !(has_fill || has_stroke) do return nil

	if rect.x == nil || rect.y == nil || rect.width == nil || rect.height == nil {
		return .INVALID_NODE
	}

	points := _rect_to_points(rect.x.?, rect.y.?, rect.width.?, rect.height.?)
	
	// Add points to poly
	for i in 0..<4 {
		append(poly_list, points[i])
	}

	// Add polygon count
	append(npolys_list, 4)

	// Add type count and types (4 lines)
	append(ntypes_list, 4)

	for i in 0..<4 {
		append(types_list, geometry.curve_type.Line)
	}

	// Add colors
	if has_fill {
		if color, err := _parse_color(rect._0.fill.?, rect._0.fill_opacity); err == nil {
			if c, ok := color.?; ok {
				append(colors_list, _vec4_to_point3dw(c))
			} else {
				append(colors_list, linalg.Point3DwF{0, 0, 0, 0})
			}
		} else {
			append(colors_list, linalg.Point3DwF{0, 0, 0, 0})
		}
	} else {
		append(colors_list, linalg.Point3DwF{0, 0, 0, 0})
	}

	// Add stroke colors and thickness
	if has_stroke {
		if color, err := _parse_color(rect._0.stroke.?, rect._0.stroke_opacity); err == nil {
			if c, ok := color.?; ok {
				append(stroke_colors_list, _vec4_to_point3dw(c))
			} else {
				append(stroke_colors_list, linalg.Point3DwF{0, 0, 0, 0})
			}
		} else {
			append(stroke_colors_list, linalg.Point3DwF{0, 0, 0, 0})
		}
	} else {
		append(stroke_colors_list, linalg.Point3DwF{0, 0, 0, 0})
	}

	if has_stroke {
		append(thickness_list, rect._0.stroke_width.?)
	} else {
		append(thickness_list, 0)
	}

	return nil
}

@private _parse_circle_to_shapes :: proc(
	poly_list: ^[dynamic]linalg.PointF,
	npolys_list: ^[dynamic]u32,
	ntypes_list: ^[dynamic]u32,
	types_list: ^[dynamic]geometry.curve_type,
	colors_list: ^[dynamic]linalg.Point3DwF,
	stroke_colors_list: ^[dynamic]linalg.Point3DwF,
	thickness_list: ^[dynamic]f32,
	circle: CIRCLE,
	allocator: mem.Allocator,
) -> (err: SVG_ERROR) {
	has_stroke := circle._0.stroke != nil && circle._0.stroke_width != nil && circle._0.stroke_width.? > 0
	has_fill := circle._0.fill != nil
	if !(has_fill || has_stroke) do return nil

	if circle.cx == nil || circle.cy == nil || circle.r == nil {
		return .INVALID_NODE
	}

	center := linalg.PointF{circle.cx.?, -circle.cy.?}
	points := _circle_to_points(center, circle.r.?)
	
	for i in 0..<4 {
		append(poly_list, points[i])
	}

	append(npolys_list, 4)
	append(ntypes_list, 1)
	append(types_list, geometry.curve_type.Unknown)

	if has_fill {
		if color, err := _parse_color(circle._0.fill.?, circle._0.fill_opacity); err == nil {
			if c, ok := color.?; ok {
				append(colors_list, _vec4_to_point3dw(c))
			} else {
				append(colors_list, linalg.Point3DwF{0, 0, 0, 0})
			}
		} else {
			append(colors_list, linalg.Point3DwF{0, 0, 0, 0})
		}
	} else {
		append(colors_list, linalg.Point3DwF{0, 0, 0, 0})
	}

	if has_stroke {
		if color, err := _parse_color(circle._0.stroke.?, circle._0.stroke_opacity); err == nil {
			if c, ok := color.?; ok {
				append(stroke_colors_list, _vec4_to_point3dw(c))
			} else {
				append(stroke_colors_list, linalg.Point3DwF{0, 0, 0, 0})
			}
		} else {
			append(stroke_colors_list, linalg.Point3DwF{0, 0, 0, 0})
		}
	} else {
		append(stroke_colors_list, linalg.Point3DwF{0, 0, 0, 0})
	}

	if has_stroke {
		append(thickness_list, circle._0.stroke_width.?)
	} else {
		append(thickness_list, 0)
	}

	return nil
}

@private _parse_ellipse_to_shapes :: proc(
	poly_list: ^[dynamic]linalg.PointF,
	npolys_list: ^[dynamic]u32,
	ntypes_list: ^[dynamic]u32,
	types_list: ^[dynamic]geometry.curve_type,
	colors_list: ^[dynamic]linalg.Point3DwF,
	stroke_colors_list: ^[dynamic]linalg.Point3DwF,
	thickness_list: ^[dynamic]f32,
	ellipse: ELLIPSE,
	allocator: mem.Allocator,
) -> (err: SVG_ERROR) {
	has_stroke := ellipse._0.stroke != nil && ellipse._0.stroke_width != nil && ellipse._0.stroke_width.? > 0
	has_fill := ellipse._0.fill != nil
	if !(has_fill || has_stroke) do return nil

	if ellipse.cx == nil || ellipse.cy == nil || ellipse.rx == nil || ellipse.ry == nil {
		return .INVALID_NODE
	}

	center := linalg.PointF{ellipse.cx.?, -ellipse.cy.?}
	points := _ellipse_to_points(center, ellipse.rx.?, ellipse.ry.?)
	
	for i in 0..<4 {
		append(poly_list, points[i])
	}

	append(npolys_list, 4)
	append(ntypes_list, 1)
	append(types_list, geometry.curve_type.Unknown)

	if has_fill {
		if color, err := _parse_color(ellipse._0.fill.?, ellipse._0.fill_opacity); err == nil {
			if c, ok := color.?; ok {
				append(colors_list, _vec4_to_point3dw(c))
			} else {
				append(colors_list, linalg.Point3DwF{0, 0, 0, 0})
			}
		} else {
			append(colors_list, linalg.Point3DwF{0, 0, 0, 0})
		}
	} else {
		append(colors_list, linalg.Point3DwF{0, 0, 0, 0})
	}

	if has_stroke {
		if color, err := _parse_color(ellipse._0.stroke.?, ellipse._0.stroke_opacity); err == nil {
			if c, ok := color.?; ok {
				append(stroke_colors_list, _vec4_to_point3dw(c))
			} else {
				append(stroke_colors_list, linalg.Point3DwF{0, 0, 0, 0})
			}
		} else {
			append(stroke_colors_list, linalg.Point3DwF{0, 0, 0, 0})
		}
	} else {
		append(stroke_colors_list, linalg.Point3DwF{0, 0, 0, 0})
	}

	if has_stroke {
		append(thickness_list, ellipse._0.stroke_width.?)
	} else {
		append(thickness_list, 0)
	}

	return nil
}

@private _parse_line_to_shapes :: proc(
	poly_list: ^[dynamic]linalg.PointF,
	npolys_list: ^[dynamic]u32,
	ntypes_list: ^[dynamic]u32,
	types_list: ^[dynamic]geometry.curve_type,
	colors_list: ^[dynamic]linalg.Point3DwF,
	stroke_colors_list: ^[dynamic]linalg.Point3DwF,
	thickness_list: ^[dynamic]f32,
	line: LINE,
	allocator: mem.Allocator,
) -> (err: SVG_ERROR) {
	has_stroke := line._0.stroke != nil && line._0.stroke_width != nil && line._0.stroke_width.? > 0
	if !has_stroke do return nil

	if line.x1 == nil || line.y1 == nil || line.x2 == nil || line.y2 == nil {
		return .INVALID_NODE
	}

	append(poly_list, linalg.PointF{line.x1.?, -line.y1.?})
	append(poly_list, linalg.PointF{line.x2.?, -line.y2.?})

	append(npolys_list, 2)
	append(ntypes_list, 1)
	append(types_list, geometry.curve_type.Line)

	append(colors_list, linalg.Point3DwF{0, 0, 0, 0})

	if color, err := _parse_color(line._0.stroke.?, line._0.stroke_opacity); err == nil {
		if c, ok := color.?; ok {
			append(stroke_colors_list, _vec4_to_point3dw(c))
		} else {
			append(stroke_colors_list, linalg.Point3DwF{0, 0, 0, 0})
		}
	} else {
		append(stroke_colors_list, linalg.Point3DwF{0, 0, 0, 0})
	}

	append(thickness_list, line._0.stroke_width.?)

	return nil
}

@private _parse_polyline_to_shapes :: proc(
	poly_list: ^[dynamic]linalg.PointF,
	npolys_list: ^[dynamic]u32,
	ntypes_list: ^[dynamic]u32,
	types_list: ^[dynamic]geometry.curve_type,
	colors_list: ^[dynamic]linalg.Point3DwF,
	stroke_colors_list: ^[dynamic]linalg.Point3DwF,
	thickness_list: ^[dynamic]f32,
	polyline: POLYLINE,
	allocator: mem.Allocator,
) -> (err: SVG_ERROR) {
	has_stroke := polyline._0.stroke != nil && polyline._0.stroke_width != nil && polyline._0.stroke_width.? > 0
	has_fill := polyline._0.fill != nil
	if !(has_fill || has_stroke) do return nil

	if polyline.points == nil || len(polyline.points.?) == 0 {
		return .INVALID_NODE
	}

	point_count := len(polyline.points.?)
	for p in polyline.points.? {
		append(poly_list, linalg.PointF{p.x, -p.y})
	}

	append(npolys_list, auto_cast point_count)
	append(ntypes_list, auto_cast (point_count - 1))

	for i in 0..<point_count - 1 {
		append(types_list, geometry.curve_type.Line)
	}

	if has_fill {
		if color, err := _parse_color(polyline._0.fill.?, polyline._0.fill_opacity); err == nil {
			if c, ok := color.?; ok {
				append(colors_list, _vec4_to_point3dw(c))
			} else {
				append(colors_list, linalg.Point3DwF{0, 0, 0, 0})
			}
		} else {
			append(colors_list, linalg.Point3DwF{0, 0, 0, 0})
		}
	} else {
		append(colors_list, linalg.Point3DwF{0, 0, 0, 0})
	}

	if has_stroke {
		if color, err := _parse_color(polyline._0.stroke.?, polyline._0.stroke_opacity); err == nil {
			if c, ok := color.?; ok {
				append(stroke_colors_list, _vec4_to_point3dw(c))
			} else {
				append(stroke_colors_list, linalg.Point3DwF{0, 0, 0, 0})
			}
		} else {
			append(stroke_colors_list, linalg.Point3DwF{0, 0, 0, 0})
		}
	} else {
		append(stroke_colors_list, linalg.Point3DwF{0, 0, 0, 0})
	}

	if has_stroke {
		append(thickness_list, polyline._0.stroke_width.?)
	} else {
		append(thickness_list, 0)
	}

	return nil
}

@private _parse_polygon_to_shapes :: proc(
	poly_list: ^[dynamic]linalg.PointF,
	npolys_list: ^[dynamic]u32,
	ntypes_list: ^[dynamic]u32,
	types_list: ^[dynamic]geometry.curve_type,
	colors_list: ^[dynamic]linalg.Point3DwF,
	stroke_colors_list: ^[dynamic]linalg.Point3DwF,
	thickness_list: ^[dynamic]f32,
	polygon: POLYGON,
	allocator: mem.Allocator,
) -> (err: SVG_ERROR) {
	has_stroke := polygon._0.stroke != nil && polygon._0.stroke_width != nil && polygon._0.stroke_width.? > 0
	has_fill := polygon._0.fill != nil
	if !(has_fill || has_stroke) do return nil

	if polygon.points == nil || len(polygon.points.?) == 0 {
		return .INVALID_NODE
	}

	point_count := len(polygon.points.?)
	for p in polygon.points.? {
		append(poly_list, linalg.PointF{p.x, -p.y})
	}

	append(npolys_list, auto_cast point_count)
	append(ntypes_list, auto_cast point_count)

	for i in 0..<point_count {
		append(types_list, geometry.curve_type.Line)
	}

	if has_fill {
		if color, err := _parse_color(polygon._0.fill.?, polygon._0.fill_opacity); err == nil {
			if c, ok := color.?; ok {
				append(colors_list, _vec4_to_point3dw(c))
			} else {
				append(colors_list, linalg.Point3DwF{0, 0, 0, 0})
			}
		} else {
			append(colors_list, linalg.Point3DwF{0, 0, 0, 0})
		}
	} else {
		append(colors_list, linalg.Point3DwF{0, 0, 0, 0})
	}

	if has_stroke {
		if color, err := _parse_color(polygon._0.stroke.?, polygon._0.stroke_opacity); err == nil {
			if c, ok := color.?; ok {
				append(stroke_colors_list, _vec4_to_point3dw(c))
			} else {
				append(stroke_colors_list, linalg.Point3DwF{0, 0, 0, 0})
			}
		} else {
			append(stroke_colors_list, linalg.Point3DwF{0, 0, 0, 0})
		}
	} else {
		append(stroke_colors_list, linalg.Point3DwF{0, 0, 0, 0})
	}

	if has_stroke {
		append(thickness_list, polygon._0.stroke_width.?)
	} else {
		append(thickness_list, 0)
	}

	return nil
}

// Helper function to mirror a point
@private _xy_mirror_point :: proc(cur: linalg.PointF, prev: linalg.PointF) -> linalg.PointF {
	return linalg.PointF{2 * cur.x - prev.x, 2 * cur.y - prev.y}
}

// Helper function to check if two points are approximately equal
@private _points_equal :: proc(a: linalg.PointF, b: linalg.PointF) -> bool {
	epsilon: f32 = 0.0001
	dx := a.x - b.x
	dy := a.y - b.y
	return (dx * dx + dy * dy) < (epsilon * epsilon)
}

@private _parse_path_to_shapes :: proc(
	poly_list: ^[dynamic]linalg.PointF,
	npolys_list: ^[dynamic]u32,
	ntypes_list: ^[dynamic]u32,
	types_list: ^[dynamic]geometry.curve_type,
	colors_list: ^[dynamic]linalg.Point3DwF,
	stroke_colors_list: ^[dynamic]linalg.Point3DwF,
	thickness_list: ^[dynamic]f32,
	path: PATH,
	allocator: mem.Allocator,
) -> (err: SVG_ERROR) {
	has_stroke := path._0.stroke != nil && path._0.stroke_width != nil && path._0.stroke_width.? > 0
	has_fill := path._0.fill != nil
	if !(path.d != nil && (has_fill || has_stroke)) do return nil

	if path.d == nil do return .INVALID_NODE
	d := path.d.?

	// Helper functions for reading path data
	_read_path_p :: proc(_str: string, i: ^int, op_: u8, cur: linalg.PointF) -> (p: linalg.PointF, ok: bool) {
		pt, pt_ok := _parse_point(_str, i)
		if !pt_ok do return {}, false
		p = linalg.PointF{pt.x, -pt.y}
		if op_ >= 'a' && op_ <= 'z' {
			p.x += cur.x
			p.y += cur.y
		}
		return p, true
	}

	_read_path_fx :: proc(_str: string, i: ^int, op_: u8, cur_x: f32) -> (f: f32, ok: bool) {
		val, val_ok := _parse_number(f32, _str, i)
		if !val_ok do return 0, false
		f = val
		if op_ >= 'a' && op_ <= 'z' {
			f += cur_x
		}
		return f, true
	}

	_read_path_fy :: proc(_str: string, i: ^int, op_: u8, cur_y: f32) -> (f: f32, ok: bool) {
		val, val_ok := _parse_number(f32, _str, i)
		if !val_ok do return 0, false
		f = -val
		if op_ >= 'a' && op_ <= 'z' {
			f += cur_y
		}
		return f, true
	}

	_read_path_r :: proc(_str: string, i: ^int) -> (r: linalg.PointF, ok: bool) {
		return _parse_point(_str, i)
	}

	// Track current subpath state
	cur := linalg.PointF{0, 0}
	start_point: linalg.PointF
	start_idx: int = -1
	start := false
	prevS: Maybe(linalg.PointF)
	prevT: Maybe(linalg.PointF)
	
	npoly: u32 = 0
	current_poly_start: int = len(poly_list)

	i := 0
	op_: Maybe(u8)

	for i < len(d) {
		// Handle Z/z (close path)
		if d[i] == 'Z' || d[i] == 'z' {
			if len(poly_list) == 0 || current_poly_start >= len(poly_list) {
				return .INVALID_NODE
			}
			// Close the path by adding a line to the start point
			last_point := poly_list[len(poly_list) - 1]
			if !_points_equal(last_point, start_point) {
				append(poly_list, start_point)
				append(types_list, geometry.curve_type.Line)
				npoly += 1
			}
			cur = start_point
			i += 1
			op_ = nil
			continue
		}

		// Skip whitespace
		for i < len(d) && (d[i] == ' ' || d[i] == '\r' || d[i] == '\n' || d[i] == '\t') {
			i += 1
		}
		if i >= len(d) do break

		// Read command if it's alphabetic
		if (d[i] >= 'a' && d[i] <= 'z') || (d[i] >= 'A' && d[i] <= 'Z') {
			op_ = d[i]
			i += 1
		}
		if i >= len(d) do break

		if op_ == nil do return .INVALID_NODE

		switch op_.? {
		case 'M', 'm':
			p, p_ok := _read_path_p(d, &i, op_.?, cur)
			if !p_ok do return .INVALID_NODE
			
			// Start new subpath
			if npoly > 0 && current_poly_start < len(poly_list) {
				append(npolys_list, npoly)
				append(ntypes_list, auto_cast npoly)
			}
			
			start_point = p
			cur = p
			current_poly_start = len(poly_list)
			npoly = 0
			start = true
			prevS = nil
			prevT = nil
			continue

		case 'L', 'l':
			if !start do return .INVALID_NODE
			p, p_ok := _read_path_p(d, &i, op_.?, cur)
			if !p_ok do return .INVALID_NODE
			
			append(poly_list, cur)
			append(poly_list, p)
			append(types_list, geometry.curve_type.Line)
			cur = p
			npoly += 1
			prevS = nil
			prevT = nil

		case 'V', 'v':
			if !start do return .INVALID_NODE
			y, y_ok := _read_path_fy(d, &i, op_.?, cur.y)
			if !y_ok do return .INVALID_NODE
			
			p := linalg.PointF{cur.x, y}
			append(poly_list, cur)
			append(poly_list, p)
			append(types_list, geometry.curve_type.Line)
			cur = p
			npoly += 1
			prevS = nil
			prevT = nil

		case 'H', 'h':
			if !start do return .INVALID_NODE
			x, x_ok := _read_path_fx(d, &i, op_.?, cur.x)
			if !x_ok do return .INVALID_NODE
			
			p := linalg.PointF{x, cur.y}
			append(poly_list, cur)
			append(poly_list, p)
			append(types_list, geometry.curve_type.Line)
			cur = p
			npoly += 1
			prevS = nil
			prevT = nil

		case 'Q', 'q':
			if !start do return .INVALID_NODE
			p1, p1_ok := _read_path_p(d, &i, op_.?, cur)
			if !p1_ok do return .INVALID_NODE
			p2, p2_ok := _read_path_p(d, &i, op_.?, cur)
			if !p2_ok do return .INVALID_NODE
			
			append(poly_list, cur)
			append(poly_list, p1)
			append(poly_list, p2)
			append(types_list, geometry.curve_type.Quadratic)
			cur = p2
			npoly += 1
			prevS = nil
			prevT = p1

		case 'C', 'c':
			if !start do return .INVALID_NODE
			p1, p1_ok := _read_path_p(d, &i, op_.?, cur)
			if !p1_ok do return .INVALID_NODE
			p2, p2_ok := _read_path_p(d, &i, op_.?, cur)
			if !p2_ok do return .INVALID_NODE
			p3, p3_ok := _read_path_p(d, &i, op_.?, cur)
			if !p3_ok do return .INVALID_NODE
			
			// Check if it's actually a quadratic (p1 == start)
			if _points_equal(p1, cur) {
				append(poly_list, cur)
				append(poly_list, p2)
				append(poly_list, p3)
				append(types_list, geometry.curve_type.Quadratic)
			} else {
				append(poly_list, cur)
				append(poly_list, p1)
				append(poly_list, p2)
				append(poly_list, p3)
				append(types_list, geometry.curve_type.Unknown)
			}
			cur = p3
			npoly += 1
			prevS = p2
			prevT = nil

		case 'S', 's':
			if !start do return .INVALID_NODE
			p1, p1_ok := _read_path_p(d, &i, op_.?, cur)
			if !p1_ok do return .INVALID_NODE
			p2, p2_ok := _read_path_p(d, &i, op_.?, cur)
			if !p2_ok do return .INVALID_NODE
			
			if prevS == nil {
				// Treat as quadratic
				append(poly_list, cur)
				append(poly_list, p1)
				append(poly_list, p2)
				append(types_list, geometry.curve_type.Quadratic)
				prevS = p1
			} else {
				// Smooth cubic: mirror previous control point
				p0 := _xy_mirror_point(cur, prevS.?)
				append(poly_list, cur)
				append(poly_list, p0)
				append(poly_list, p1)
				append(poly_list, p2)
				append(types_list, geometry.curve_type.Unknown)
				prevS = p1
			}
			cur = p2
			npoly += 1
			prevT = nil

		case 'T', 't':
			if !start do return .INVALID_NODE
			p, p_ok := _read_path_p(d, &i, op_.?, cur)
			if !p_ok do return .INVALID_NODE
			
			if prevT == nil {
				// Treat as line
				append(poly_list, cur)
				append(poly_list, p)
				append(types_list, geometry.curve_type.Line)
			} else {
				// Smooth quadratic: mirror previous control point
				p0 := _xy_mirror_point(cur, prevT.?)
				append(poly_list, cur)
				append(poly_list, p0)
				append(poly_list, p)
				append(types_list, geometry.curve_type.Quadratic)
				prevT = p0
			}
			cur = p
			npoly += 1
			prevS = nil

		case 'A', 'a':
			if !start do return .INVALID_NODE
			prevS = nil
			prevT = nil

			r, r_ok := _read_path_r(d, &i)
			if !r_ok do return .INVALID_NODE
			
			x_angle, x_angle_ok := _parse_number(f32, d, &i)
			if !x_angle_ok do return .INVALID_NODE
			x_angle = x_angle * math.PI * 2.0 / 360.0
			
			large_arc, large_arc_ok := _parse_bool(d, &i)
			if !large_arc_ok do return .INVALID_NODE
			
			sweep, sweep_ok := _parse_bool(d, &i)
			if !sweep_ok do return .INVALID_NODE
			
			end, end_ok := _read_path_p(d, &i, op_.?, cur)
			if !end_ok do return .INVALID_NODE
			
			// Arc to cubic bezier conversion
			// Simplified version - convert arc to line if degenerate
			cur_y_flipped := linalg.PointF{cur.x, -cur.y}
			end_y_flipped := linalg.PointF{end.x, -end.y}
			
			pp := linalg.PointF{
				math.cos(x_angle) * (cur_y_flipped.x - end_y_flipped.x) / 2.0 + math.sin(x_angle) * (cur_y_flipped.y - end_y_flipped.y) / 2.0,
				-math.sin(x_angle) * (cur_y_flipped.x - end_y_flipped.x) / 2.0 + math.cos(x_angle) * (cur_y_flipped.y - end_y_flipped.y) / 2.0,
			}
			
			if (pp.x == 0 && pp.y == 0) || (r.x == 0 || r.y == 0) {
				// Degenerate arc - convert to line
				append(poly_list, cur)
				append(poly_list, end)
				append(types_list, geometry.curve_type.Line)
				cur = end
				npoly += 1
			} else {
				// Full arc conversion to cubic bezier segments
				// This is a simplified version - for full implementation, see the Zig code
				// For now, approximate as a single cubic bezier
				r_abs := linalg.PointF{math.abs(r.x), math.abs(r.y)}
				
				lambda := (pp.x * pp.x) / (r_abs.x * r_abs.x) + (pp.y * pp.y) / (r_abs.y * r_abs.y)
				if lambda > 1 {
					scale := math.sqrt_f32(lambda)
					r_abs.x *= scale
					r_abs.y *= scale
				}
				
				// Simplified: convert to single cubic bezier approximation
				// Full implementation would split into multiple segments
				mid := linalg.PointF{(cur.x + end.x) / 2.0, (cur.y + end.y) / 2.0}
				ctrl1 := linalg.PointF{cur.x + (end.x - cur.x) / 3.0, cur.y + (end.y - cur.y) / 3.0}
				ctrl2 := linalg.PointF{cur.x + 2.0 * (end.x - cur.x) / 3.0, cur.y + 2.0 * (end.y - cur.y) / 3.0}
				
				append(poly_list, cur)
				append(poly_list, ctrl1)
				append(poly_list, ctrl2)
				append(poly_list, end)
				append(types_list, geometry.curve_type.Unknown)
				cur = end
				npoly += 1
			}
			continue

		case:
			return .INVALID_NODE
		}
	}

	if len(poly_list) == 0 || current_poly_start >= len(poly_list) {
		return .INVALID_NODE
	}

	// Finalize last polygon
	if npoly > 0 {
		append(npolys_list, npoly)
		append(ntypes_list, auto_cast npoly)
	}

	// Add colors
	if has_fill {
		if color, err := _parse_color(path._0.fill.?, path._0.fill_opacity); err == nil {
			if c, ok := color.?; ok {
				append(colors_list, _vec4_to_point3dw(c))
			} else {
				append(colors_list, linalg.Point3DwF{0, 0, 0, 0})
			}
		} else {
			append(colors_list, linalg.Point3DwF{0, 0, 0, 0})
		}
	} else {
		append(colors_list, linalg.Point3DwF{0, 0, 0, 0})
	}

	if has_stroke {
		if color, err := _parse_color(path._0.stroke.?, path._0.stroke_opacity); err == nil {
			if c, ok := color.?; ok {
				append(stroke_colors_list, _vec4_to_point3dw(c))
			} else {
				append(stroke_colors_list, linalg.Point3DwF{0, 0, 0, 0})
			}
		} else {
			append(stroke_colors_list, linalg.Point3DwF{0, 0, 0, 0})
		}
	} else {
		append(stroke_colors_list, linalg.Point3DwF{0, 0, 0, 0})
	}

	if has_stroke {
		append(thickness_list, path._0.stroke_width.?)
	} else {
		append(thickness_list, 0)
	}

	return nil
}

