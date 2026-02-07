package font

import "base:runtime"
import "core:c"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:slice"
import "core:sync"
import "core:unicode"
import "core:unicode/utf8"
import "core:engine/geometry"
import "vendor:freetype"
import "../"
import "core:log"


font :: struct {}

@(private) font_t :: struct {
    face:freetype.Face,
    mutex:sync.Mutex,

    scale:f32,//default 256
    allocator:mem.Allocator,
}

@(private) char_data :: struct {
    advance_x:f32,
    shapes:Maybe(geometry.shapes),
}

@(private) SCALE_DEFAULT : f32 : 256


font_render_opt :: struct {
    scale:linalg.point,    //(0,0) -> (1,1)
    offset:linalg.point,
    pivot:linalg.point,
    stroke_color:linalg.point3dw,//if thickness == 0, ignore
    color:Maybe(linalg.point3dw),
    area:Maybe(linalg.point),
    thickness:f32,//if 0, no stroke
}

font_render_opt2 :: struct {
    opt:font_render_opt,
    ranges:[]font_render_range,
}

font_render_range :: struct {
    font:^font,
    scale:linalg.point,    //(0,0) -> (1,1)
    color:linalg.point3dw,
    len:uint,
}


@(private) freetype_lib:freetype.Library = nil

@(private) _init_freetype :: proc () {
    err := freetype.init_free_type(&freetype_lib)
    if err != .Ok do log.panicf("init_freetype: %s\n", err)
}

@(private, fini) _deinit_freetype :: proc "contextless" () {
    if (freetype_lib != nil) {
        err := freetype.done_free_type(freetype_lib)
        if err != .Ok do panic_contextless("done_free_type\n")
        freetype_lib = nil
    }
}

freetype_err :: union #shared_nil {
    freetype.Error,
    mem.Allocator_Error,
}

/*
Initializes a font from font data

Inputs:
- _fontData: Font file data as bytes
- _faceIdx: Face index in the font file (default: 0)
- allocator: Allocator to use (default: context.allocator)

Returns:
- Pointer to the initialized font, or nil on error
- An error if initialization failed
- Allocator error if allocation failed
*/
font_init :: proc(_fontData:[]byte, #any_int _faceIdx:int = 0, allocator:mem.Allocator = context.allocator) -> (font : ^font = nil, err : freetype_err = nil) {
    font_, alloc_err := mem.new_non_zeroed(font_t, allocator)
    if alloc_err != nil {
        err = alloc_err
        return
    }
    defer if err != nil do free(font_, allocator)

    font_.scale = SCALE_DEFAULT
    font_.mutex = {}

    if freetype_lib == nil do _init_freetype()

    ft_err := freetype.new_memory_face(freetype_lib, raw_data(_fontData), auto_cast len(_fontData), auto_cast _faceIdx, &font_.face)
    if ft_err != .Ok {
        err = ft_err
        return
    }

    defer if err != nil {
        freetype.done_face(font_.face)
    }  

    ft_err = freetype.set_char_size(font_.face, 0, 16 * 256 * 64, 0, 0)
    if ft_err != .Ok {
        err = ft_err
        return
    }

    font_.allocator = allocator
    font = auto_cast font_
    return
}

font_deinit :: proc(self:^font) -> (err : freetype_err = nil) {
    self_:^font_t = auto_cast self
    sync.mutex_lock(&self_.mutex)

    err = freetype.done_face(self_.face)
    if err != nil do log.panicf("done_face: %s\n", err)

    sync.mutex_unlock(&self_.mutex)
    free(self_, self_.allocator)

    return
}

/*
Sets the scale of the font

Inputs:
- self: Pointer to the font
- scale: Scale factor for the font

Returns:
- None
*/
font_set_scale :: proc(self:^font, scale:f32) {
    self_:^font_t = auto_cast self
    sync.mutex_lock(&self_.mutex)
    self_.scale = SCALE_DEFAULT / scale
    sync.mutex_unlock(&self_.mutex)
}

font_render_string2 :: proc(_str:string,
_renderOpt:font_render_opt2,
allocator : runtime.Allocator) -> (shapes:geometry.shapes, err:geometry.shape_error = nil) {
    i : int = 0
    opt := _renderOpt.opt
	
	nodes := mem.make_non_zeroed([dynamic]geometry.shape_node, context.temp_allocator) or_return
	defer delete(nodes)

    for r in _renderOpt.ranges {
        opt.scale = _renderOpt.opt.scale * r.scale
        opt.color = r.color

        if r.len == 0 || i + auto_cast r.len >= len(_str) {
            _font_render_string(auto_cast r.font, _str[i:], opt, &nodes,  &shapes.rect, allocator) or_return
            break;
        } else {
            _font_render_string(auto_cast r.font, _str[i:i + auto_cast r.len], opt, &nodes, &shapes.rect, allocator) or_return
            i += auto_cast r.len
        }
    }
    shapes.nodes = mem.make_non_zeroed([]geometry.shape_node, len(nodes), allocator) or_return
    mem.copy_non_overlapping(raw_data(shapes.nodes), raw_data(nodes), len(nodes) * size_of(geometry.shape_node))
    return
}
//input _vertArr and _indArr must use context.temp_allocator
@(private="file") _font_render_string :: proc(self:^font_t,
    _str:string,
    _renderOpt:font_render_opt, nodes:^[dynamic]geometry.shape_node, rect:^linalg.rect,
    allocator : runtime.Allocator) -> (err:geometry.shape_error = nil) {

    maxP : linalg.point = {min(f32), min(f32)}
    minP : linalg.point = {max(f32), max(f32)}

    offset : linalg.point = {}

	shape_old_len := len(nodes^)
    sync.mutex_lock(&self.mutex)
	defer sync.mutex_unlock(&self.mutex)
    for s in _str {
        if _renderOpt.area != nil && offset.y <= -_renderOpt.area.?.y do break
        if s == '\n' {
            offset.y -= f32(self.face.size.metrics.height) / (64.0 * self.scale) 
            offset.x = 0
            continue
        }
        minP = math.min_array(minP, offset)

        if _renderOpt.color == nil && _renderOpt.thickness == 0.0 {
            err = .EmptyColor
            return
        }
        _font_render_char(self, s, &offset, nodes,  _renderOpt.area, _renderOpt.scale,
             _renderOpt.color, _renderOpt.stroke_color, _renderOpt.thickness, allocator) or_return
        
        maxP = math.max_array(maxP,linalg.point{offset.x, offset.y + f32(self.face.size.metrics.height) / (64.0 * self.scale) })
    }
    if len(nodes^) == shape_old_len {
        err = .EmptyPolygon
        return
    }

    size : linalg.point = _renderOpt.area != nil ? _renderOpt.area.? : (maxP - minP) * linalg.point{1,1}

    maxP = {min(f32), min(f32)}
    minP = {max(f32), max(f32)}

    for &v in nodes^ {
		for &l in v.lines {
			l.start = l.start - _renderOpt.pivot * size * _renderOpt.scale + _renderOpt.offset
			minP = math.min_array(minP, l.start)
			maxP = math.max_array(maxP, l.start)
			l.end = l.end - _renderOpt.pivot * size * _renderOpt.scale + _renderOpt.offset
			minP = math.min_array(minP, l.end)
			maxP = math.max_array(maxP, l.end)
			if l.type != .Line {
				l.control0 = l.control0 - _renderOpt.pivot * size * _renderOpt.scale + _renderOpt.offset
				minP = math.min_array(minP, l.control0)
				maxP = math.max_array(maxP, l.control0)
				if l.type != .Quadratic {
					l.control1 = l.control1 - _renderOpt.pivot * size * _renderOpt.scale + _renderOpt.offset
					maxP = math.max_array(maxP, l.control1)
					minP = math.min_array(minP, l.control1)
				}
			}
		}
    }
    rect^ = linalg.Rect_Init(minP.x, maxP.x, maxP.y, minP.y)

    subX :f32 = rect^.left + (rect^.right - rect^.left) / 2.0
    subY :f32 = -rect^.top + (rect^.top - rect^.bottom) / 2.0//remove rect.pos xy
    for &n in nodes^ {//move to center
        for &l in n.lines {
            l.start.x -= subX
            l.start.y += subY
            l.end.x -= subX
            l.end.y += subY
			if l.type != .Line {
				l.control0.x -= subX
				l.control0.y += subY
			} else if l.type != .Quadratic {
				l.control1.x -= subX
				l.control1.y += subY
			}
        }
    }
	tmpr := rect^
    rect^.left = -(tmpr.right - tmpr.left) / 2.0
    rect^.top = (tmpr.top - tmpr.bottom) / 2.0
	rect^.bottom = -(tmpr.top - tmpr.bottom) / 2.0
    rect^.right = (tmpr.right - tmpr.left) / 2.0
    return
}

@(private="file") _font_render_char :: proc(self:^font_t,
    _char:rune,
    offset:^linalg.point,
	nodes:^[dynamic]geometry.shape_node,
    area:Maybe(linalg.point),
    scale:linalg.point,
    color:Maybe(linalg.point3dw),
    stroke_color:linalg.point3dw,
    thickness:f32,
	allocator : runtime.Allocator,
) -> (shapeErr:geometry.shape_error = nil) {
    FTMoveTo :: proc "c" (to: ^freetype.Vector, user: rawptr) -> c.int {
        data : ^font_user_data = auto_cast user
		context = data.context_

        data.pen = linalg.point{f32(to.x) / (64 * data.scale), f32(to.y) / (64 * data.scale)}

        if data.lineCount > 0 {
            data.polygonCount += 1
            data.lineCount = 0
        }
		data.lines_da[data.polygonCount] = mem.make_non_zeroed([dynamic]geometry.shape_line, context.temp_allocator)
        return 0
    }
    FTLineTo :: proc "c" (to: ^freetype.Vector, user: rawptr) -> c.int {
        data : ^font_user_data = auto_cast user
		context = data.context_

        end := linalg.point{f32(to.x) / (64 * data.scale), f32(to.y) / (64 * data.scale)}
    
        non_zero_append(&data.lines_da[data.polygonCount], geometry.shape_line{
            start = data.pen,
            control0 = {0, 0},
            control1 = {0, 0},
            end = end,
            type = .Line,
        })
        data.pen = end
        data.lineCount += 1
        return 0
    }
    FTConicTo :: proc "c" (control: ^freetype.Vector, to: ^freetype.Vector, user: rawptr) -> c.int {
        data : ^font_user_data = auto_cast user
		context = data.context_

        ctl := linalg.point{f32(control.x) / (64 * data.scale), f32(control.y) / (64 * data.scale)}
        end := linalg.point{f32(to.x) / (64 * data.scale), f32(to.y) / (64 * data.scale)}
    
        non_zero_append(&data.lines_da[data.polygonCount], geometry.shape_line{
            start = data.pen,
            control0 = ctl,
            end = end,
            type = .Quadratic,
        })
        data.pen = end
        data.lineCount += 1
        return 0
    }
    FTCubicTo :: proc "c" (control0, control1, to: ^freetype.Vector, user: rawptr) -> c.int {
        data : ^font_user_data = auto_cast user
		context = data.context_

        ctl0 := linalg.point{f32(control0.x) / (64 * data.scale), f32(control0.y) / (64 * data.scale)}
        ctl1 := linalg.point{f32(control1.x) / (64 * data.scale), f32(control1.y) / (64 * data.scale)}
        end := linalg.point{f32(to.x) / (64 * data.scale), f32(to.y) / (64 * data.scale)}
    
        non_zero_append(&data.lines_da[data.polygonCount], geometry.shape_line{
            start = data.pen,
            control0 = ctl0,
            control1 = ctl1,
            end = end,
            type = .Unknown,
        })
        data.pen = end
        data.lineCount += 1
        return 0
    }
    font_user_data :: struct {
        pen : linalg.point,
		lines_da:[][dynamic]geometry.shape_line,
        lineCount : u32,
        polygonCount : u32,
        scale : f32,
		context_:runtime.Context,
    }
    @static funcs : freetype.Outline_Funcs = {
        move_to = FTMoveTo,
        line_to = FTLineTo,
        conic_to = FTConicTo,
        cubic_to = FTCubicTo,
    }

	charD:char_data
	ch := _char
	for {
		fIdx := freetype.get_char_index(self.face, auto_cast ch)
		if fIdx == 0 {
			if ch == '□' do log.panicf("not found □\n")
			ch = '□'
			continue
		}
		err := freetype.load_glyph(self.face, fIdx, {.No_Bitmap})
		if err != .Ok do log.panicf("load_glyph: %s\n", err)

		if self.face.glyph.outline.n_points == 0 {
			charD = {
				advance_x = f32(self.face.glyph.advance.x) / (64.0 * self.scale),
				shapes = nil,
			}
			break
		}

		//TODO (xfitgd) FT_Outline_New FT_Outline_Copy FT_Outline_Done로 임시객체로 복제하여 Lock Free 구현
		if freetype.outline_get_orientation(&self.face.glyph.outline) == freetype.Orientation.FILL_RIGHT {
			freetype.outline_reverse(&self.face.glyph.outline)
		}

		// 최대 폴리곤 개수는 n_contours와 같음
		max_polygons := self.face.glyph.outline.n_contours
		
		data : font_user_data = {
			context_ = context,
			lineCount = 0,
			polygonCount = 0,
			scale = self.scale,
			lines_da = mem.make_non_zeroed([][dynamic]geometry.shape_line, max_polygons, size_of(uint) << 3, context.temp_allocator),
		}
		defer {
			for lines in data.lines_da {
				delete(lines)
			}
			delete(data.lines_da, context.temp_allocator)
		}
	
		err = freetype.outline_decompose(&self.face.glyph.outline, &funcs, &data)
		if err != .Ok do log.panicf("outline_decompose: %s\n", err)

		if data.lineCount == 0 {
			charD = {
				advance_x = f32(self.face.glyph.advance.x) / (64.0 * self.scale),
				shapes = nil
			}
			break
		} else {
			// 마지막 폴리곤의 선분 개수 추가
			if data.lineCount > 0 {
				data.polygonCount += 1
			}
			poly := geometry.shapes{}
			poly.nodes = mem.make_non_zeroed_aligned_slice([]geometry.shape_node, data.polygonCount, size_of(uint) << 3, context.temp_allocator)
			for i in 0..<data.polygonCount {
				poly.nodes[i].lines = mem.make_non_zeroed_aligned_slice([]geometry.shape_line, len(data.lines_da[i]), size_of(uint) << 3, allocator)
				mem.copy_non_overlapping(&poly.nodes[i].lines[0], &data.lines_da[i][0], size_of(geometry.shape_line) * len(data.lines_da[i]))
				poly.nodes[i].color = linalg.point3dw{0,0,0,2}
				poly.nodes[i].stroke_color = linalg.point3dw{0,0,0,1}
				poly.nodes[i].thickness = thickness
			}
			
			if shapeErr != nil do return
			
			charD = {
				advance_x = f32(self.face.glyph.advance.x) / (64.0 * self.scale),
				shapes = poly,
			}
		}	
		break
	}
	defer if charD.shapes != nil {
		delete(charD.shapes.?.nodes, context.temp_allocator)
	}
    ww := charD.shapes == nil ? charD.advance_x : charD.shapes.?.rect.right
    if area != nil && offset.x + ww >= area.?.x {
        offset.y -= f32(self.face.size.metrics.height) / (64.0 * self.scale) 
        offset.x = 0
        if offset.y <= -area.?.y do return
    }
	if charD.shapes != nil {
		vlen := len(nodes^)

		non_zero_append(nodes, ..charD.shapes.?.nodes[:])
		for &node in nodes^[vlen:] {
			for &line in node.lines {
				line.start += offset^
				line.start *= scale
				line.end += offset^
				line.end *= scale
				if line.type != .Line {
					line.control0 += offset^
					line.control0 *= scale
					if line.type != .Quadratic {
						line.control1 += offset^
						line.control1 *= scale
					}
				}
			}
			if node.color.a == 1.0 {
				node.color = stroke_color
			} else if node.color.a == 2.0 {
				node.color = color.?
			}
		}
	}
    offset.x += charD.advance_x
    return
}

font_render_string :: proc(self:^font, _str:string, _renderOpt:font_render_opt, allocator := context.allocator) -> (res:geometry.shapes, err:geometry.shape_error = nil) {
	if self == nil do log.panicf("font_render_string: font is nil\n")

    nodes := mem.make_non_zeroed([dynamic]geometry.shape_node, context.temp_allocator) or_return
    defer delete(nodes)

    _font_render_string(auto_cast self, _str, _renderOpt, &nodes, &res.rect, allocator) or_return

	res.nodes = mem.make_non_zeroed([]geometry.shape_node, len(nodes), allocator) or_return
	mem.copy_non_overlapping(raw_data(res.nodes), raw_data(nodes), len(nodes) * size_of(geometry.shape_node))
    return
}