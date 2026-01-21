package font

import "base:runtime"
import "core:c"
import "core:debug/trace"
import "core:fmt"
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


@(private="file") char_data :: struct {
    raw_shape : ^geometry.raw_shape,
    advance_x : f32,
}
@(private="file") char_node :: struct #packed {
    size:u32,
    char:rune,
    advance_x:f32,
}

font :: struct {}

@(private) FONT_KEY :: struct #packed {
    char:rune,
    thickness:f32,//0 -> no stroke, > 0 -> stroke, < 0 -> stroke and fill
}

@(private) font_t :: struct {
    face:freetype.Face,
    char_array : map[FONT_KEY]char_data,

    mutex:sync.Mutex,

    scale:f32,//default 256
    allocator:mem.Allocator,
}

@(private="file") SCALE_DEFAULT : f32 : 256


font_render_opt :: struct {
    scale:linalg.PointF,    //(0,0) -> (1,1)
    offset:linalg.PointF,
    pivot:linalg.PointF,
    area:Maybe(linalg.PointF),
    color:Maybe(linalg.Point3DwF),
    stroke_color:linalg.Point3DwF,//if thickness == 0, ignore
    thickness:f32,//if 0, no stroke
    flag:engine.resource_usage,
}

font_render_opt2 :: struct {
    opt:font_render_opt,
    ranges:[]font_render_range,
}

font_render_range :: struct {
    font:^font,
    scale:linalg.PointF,    //(0,0) -> (1,1)
    color:linalg.Point3DwF,
    len:uint,
}


@(private) freetype_lib:freetype.Library = nil

@(private) _init_freetype :: proc "contextless" () {
    err := freetype.init_free_type(&freetype_lib)
    if err != .Ok do trace.panic_log(err)
}

@(private, fini) _deinit_freetype :: proc "contextless" () {
    if (freetype_lib != nil) {
        err := freetype.done_free_type(freetype_lib)
        if err != .Ok do trace.panic_log(err)
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

    font_.char_array = make_map( map[FONT_KEY]char_data, allocator )
    defer if err != nil do delete(font_.char_array)

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

/*
Deinitializes and cleans up font resources

Inputs:
- self: Pointer to the font to deinitialize

Returns:
- An error if deinitialization failed
*/
font_deinit :: proc(self:^font) -> (err : freetype_err = nil) {
    self_:^font_t = auto_cast self
    sync.mutex_lock(&self_.mutex)

    err = freetype.done_face(self_.face)
    if err != nil do trace.panic_log(err)

    for key,value in self_.char_array {
        geometry.raw_shape_free(value.raw_shape, self_.allocator)
    }
    delete(self_.char_array)
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

@(private="file") _font_render_string2 :: proc(_str:string,
_renderOpt:font_render_opt2,
vertList:^[dynamic]geometry.shape_vertex2d,
indList:^[dynamic]u32,
allocator : runtime.Allocator) -> (rect:linalg.RectF, err:geometry.shape_error = nil) {
    i : int = 0
    opt := _renderOpt.opt
    rectT : linalg.RectF
    rect = linalg.Rect_Init(f32(0.0), 0.0, 0.0, 0.0)

    for r in _renderOpt.ranges {
        opt.scale = _renderOpt.opt.scale * r.scale
        opt.color = r.color

        if r.len == 0 || i + auto_cast r.len >= len(_str) {
            _, rectT = _font_render_string(auto_cast r.font, _str[i:], opt, vertList, indList) or_return
            rect = linalg.Rect_Or(rect, rectT)
            break;
        } else {
            opt.offset, rectT = _font_render_string(auto_cast r.font, _str[i:i + auto_cast r.len], opt, vertList, indList) or_return
            rect = linalg.Rect_Or(rect, rectT)
            i += auto_cast r.len
        }
    }
    return
}
//input _vertArr and _indArr must use context.temp_allocator
@(private="file") _font_render_string :: proc(self:^font_t,
    _str:string,
    _renderOpt:font_render_opt,
    _vertArr:^[dynamic]geometry.shape_vertex2d,
    _indArr:^[dynamic]u32) -> (pt:linalg.PointF, rect:linalg.RectF, err:geometry.shape_error = nil) {

    maxP : linalg.PointF = {min(f32), min(f32)}
    minP : linalg.PointF = {max(f32), max(f32)}

    offset : linalg.PointF = {}

    sync.mutex_lock(&self.mutex)
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
        _font_render_char(self, s, _vertArr, _indArr, &offset, _renderOpt.area, _renderOpt.scale,
             _renderOpt.color, _renderOpt.stroke_color, _renderOpt.thickness) or_return
        
        maxP = math.max_array(maxP,linalg.PointF{offset.x, offset.y + f32(self.face.size.metrics.height) / (64.0 * self.scale) })
    }
    sync.mutex_unlock(&self.mutex)
    if len(_vertArr) == 0 {
        err = .EmptyPolygon
        return
    }

    size : linalg.PointF = _renderOpt.area != nil ? _renderOpt.area.? : (maxP - minP) * linalg.PointF{1,1}

    maxP = {min(f32), min(f32)}
    minP = {max(f32), max(f32)}

    for &v in _vertArr^ {
        v.pos -= _renderOpt.pivot * size * _renderOpt.scale
        v.pos += _renderOpt.offset

        minP = math.min_array(minP, v.pos)
        maxP = math.max_array(maxP, v.pos)
    }
    rect = linalg.Rect_Init(minP.x, maxP.x, maxP.y, minP.y)

    subX :f32 = rect.left + (rect.right - rect.left) / 2.0
    subY :f32 = -rect.top + (rect.top - rect.bottom) / 2.0//remove rect.pos xy
    for &v in _vertArr^ {//move to center
        v.pos.x -= subX
        v.pos.y += subY
    }
	tmpr := rect
    rect.left = -(tmpr.right - tmpr.left) / 2.0
    rect.top = (tmpr.top - tmpr.bottom) / 2.0
	rect.bottom = -(tmpr.top - tmpr.bottom) / 2.0
    rect.right = (tmpr.right - tmpr.left) / 2.0

    pt = offset * _renderOpt.scale + _renderOpt.offset
    return
}

@(private="file") _font_render_char :: proc(self:^font_t,
    _char:rune,
    _vertArr:^[dynamic]geometry.shape_vertex2d,
    _indArr:^[dynamic]u32,
    offset:^linalg.PointF,
    area:Maybe(linalg.PointF),
    scale:linalg.PointF,
    color:Maybe(linalg.Point3DwF),
    stroke_color:linalg.Point3DwF,
    thickness:f32,
) -> (shapeErr:geometry.shape_error = nil) {
    ok := FONT_KEY{_char, thickness} in self.char_array
    charD : ^char_data

    FTMoveTo :: proc "c" (to: ^freetype.Vector, user: rawptr) -> c.int {
        data : ^font_user_data = auto_cast user
		context = data.context_

        data.pen = linalg.PointF{f32(to.x) / (64 * data.scale), f32(to.y) / (64 * data.scale)}

        if data.lineCount > 0 {
            data.polygonCount += 1
            data.lineCount = 0
        }
        return 0
    }
    FTLineTo :: proc "c" (to: ^freetype.Vector, user: rawptr) -> c.int {
        data : ^font_user_data = auto_cast user
		context = data.context_

        end := linalg.PointF{f32(to.x) / (64 * data.scale), f32(to.y) / (64 * data.scale)}
    
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

        ctl := linalg.PointF{f32(control.x) / (64 * data.scale), f32(control.y) / (64 * data.scale)}
        end := linalg.PointF{f32(to.x) / (64 * data.scale), f32(to.y) / (64 * data.scale)}
    
        non_zero_append(&data.lines_da[data.polygonCount], geometry.shape_line{
            start = data.pen,
            control0 = geometry.CvtQuadraticToCubic0(data.pen, ctl),
            control1 = geometry.CvtQuadraticToCubic1(end, ctl),
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

        ctl0 := linalg.PointF{f32(control0.x) / (64 * data.scale), f32(control0.y) / (64 * data.scale)}
        ctl1 := linalg.PointF{f32(control1.x) / (64 * data.scale), f32(control1.y) / (64 * data.scale)}
        end := linalg.PointF{f32(to.x) / (64 * data.scale), f32(to.y) / (64 * data.scale)}
    
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
        pen : linalg.PointF,
        nodes : []geometry.shape_node,
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

    thickness2 := color != nil ? -thickness : thickness
    thickness2 = f32(int(thickness2 * 10000 / 10000)) //소수점 아래 4자리 이하로 자른다. //!need test

    if ok {
        charD = &self.char_array[FONT_KEY{_char, thickness2}]
    } else {
        ch := _char
        for {
            fIdx := freetype.get_char_index(self.face, auto_cast ch)
            if fIdx == 0 {
                if ch == '□' do trace.panic_log("not found □")
                ok = FONT_KEY{'□', thickness2} in self.char_array
                if ok {
                    charD = &self.char_array[FONT_KEY{'□', thickness2}]
                    break
                }
                ch = '□'

                continue
            }
            err := freetype.load_glyph(self.face, fIdx, {.No_Bitmap})
            if err != .Ok do trace.panic_log(err)

            if self.face.glyph.outline.n_points == 0 {
                charData : char_data = {
                    advance_x = f32(self.face.glyph.advance.x) / (64.0 * SCALE_DEFAULT),
                    raw_shape = nil,
                }
                self.char_array[FONT_KEY{ch, thickness2}] = charData

                charD = &self.char_array[FONT_KEY{ch, thickness2}]
                break
            }
    
            //TODO (xfitgd) FT_Outline_New FT_Outline_Copy FT_Outline_Done로 임시객체로 복제하여 Lock Free 구현
            if freetype.outline_get_orientation(&self.face.glyph.outline) == freetype.Orientation.FILL_RIGHT {
                freetype.outline_reverse(&self.face.glyph.outline)
            }

            // 최대 폴리곤 개수는 n_contours와 같음
            max_polygons := self.face.glyph.outline.n_contours
            nodes_slice := mem.make_non_zeroed([]geometry.shape_node, max_polygons, 64, context.temp_allocator)
            defer delete(nodes_slice, context.temp_allocator)
            
            data : font_user_data = {
				context_ = context,
                lineCount = 0,
                nodes = nodes_slice,
                polygonCount = 0,
                scale = self.scale,
				lines_da = mem.make_non_zeroed([][dynamic]geometry.shape_line, max_polygons, 64, context.temp_allocator),
            }
			defer {
				for lines in data.lines_da {
					delete(lines)
				}
				delete(data.lines_da, context.temp_allocator)
			}
        
            err = freetype.outline_decompose(&self.face.glyph.outline, &funcs, &data)
            if err != .Ok do trace.panic_log(err)

            charData : char_data
            if data.lineCount == 0 {
                charData = {
                    advance_x = f32(self.face.glyph.advance.x) / (64.0 * self.scale),
                    raw_shape = nil
                }
                self.char_array[FONT_KEY{ch, thickness2}] = charData
            
                charD = &self.char_array[FONT_KEY{ch, thickness2}]
                break
            } else {
                sync.mutex_unlock(&self.mutex)// else 부분은 mutex 해제 후 작업 후 다시 잠금
                defer sync.mutex_lock(&self.mutex)
               
                // 마지막 폴리곤의 선분 개수 추가
                if data.lineCount > 0 {
					data.polygonCount += 1
                }
				for i in 0..<data.polygonCount {
					data.nodes[i].lines = data.lines_da[i][:]
					data.nodes[i].color = linalg.Point3DwF{0,0,0,2}
					data.nodes[i].stroke_color = linalg.Point3DwF{0,0,0,1}
					data.nodes[i].thickness = thickness
				}
                poly := geometry.shapes{
                    nodes = data.nodes[:data.polygonCount],
                }

                rawP : ^geometry.raw_shape
                rawP , shapeErr = geometry.shapes_compute_polygon(&poly, self.allocator)//높은 부하 작업 High load operations		
                defer if shapeErr != nil {
                    geometry.raw_shape_free(rawP, self.allocator)
                }

                if shapeErr != nil do return

                // if len(rawP.vertices) > 0 {
                //     maxP :linalg.PointF = {min(f32), min(f32)}
                //     minP :linalg.PointF = {max(f32), max(f32)}

                //     for v in rawP.vertices {
                //         minP = math.min_array(minP, v.pos)
                //         maxP = math.max_array(maxP, v.pos)
                //     }
                //     rawP.rect = linalg.Rect_Init_LTRB(minP.x, maxP.x, maxP.y, minP.y)
                // }

                charData = {
                    advance_x = f32(self.face.glyph.advance.x) / (64.0 * self.scale),
                    raw_shape = rawP,
                }
            }
            self.char_array[FONT_KEY{ch, thickness2}] = charData
            
            charD = &self.char_array[FONT_KEY{ch, thickness2}]
            break
        }
    }
    ww := charD.raw_shape == nil ? charD.advance_x : charD.raw_shape.rect.right
    if area != nil && offset.x + ww >= area.?.x {
        offset.y -= f32(self.face.size.metrics.height) / (64.0 * self.scale) 
        offset.x = 0
        if offset.y <= -area.?.y do return
    }
   if charD.raw_shape != nil {
        vlen := len(_vertArr^)

        non_zero_resize_dynamic_array(_vertArr, vlen + len(charD.raw_shape.vertices))
        runtime.mem_copy_non_overlapping(&_vertArr^[vlen], &charD.raw_shape.vertices[0], len(charD.raw_shape.vertices) * size_of(geometry.shape_vertex2d))

        i := vlen
        for ;i < len(_vertArr^);i += 1 {
            _vertArr^[i].pos += offset^
            _vertArr^[i].pos *= scale
            if _vertArr^[i].color.a == 1.0 {
                _vertArr^[i].color = stroke_color
            } else if _vertArr^[i].color.a == 2.0 {
                _vertArr^[i].color = color.?
            }
        }

        ilen := len(_indArr^)
        non_zero_resize_dynamic_array(_indArr, ilen + len(charD.raw_shape.indices))
        runtime.mem_copy_non_overlapping(&_indArr^[ilen], &charD.raw_shape.indices[0], len(charD.raw_shape.indices) * size_of(u32))

        i = ilen
        for ;i < len(_indArr^);i += 1 {
            _indArr^[i] += auto_cast vlen
        }
    }
    offset.x += charD.advance_x

    return
}

font_render_string2 :: proc(_str:string, _renderOpt:font_render_opt2, allocator := context.allocator) -> (res:^geometry.raw_shape, err:geometry.shape_error = nil) {
    vertList := make([dynamic]geometry.shape_vertex2d, allocator) or_return
    defer if err != nil do delete(vertList)

    indList := make([dynamic]u32, allocator) or_return
    defer if err != nil do delete(indList)

    _font_render_string2(_str, _renderOpt, &vertList, &indList, allocator) or_return
    shrink(&vertList)
    shrink(&indList)
    res = new (geometry.raw_shape, allocator) or_return
    res^ = {
        vertices = vertList[:],
        indices = indList[:],
    }
    return
}


/*
Renders a string using the font

Inputs:
- self: Pointer to the font
- _str: String to render
- _renderOpt: Rendering options
- allocator: Allocator to use (default: context.allocator)

Returns:
- Pointer to the raw shape containing the rendered geometry
- An error if rendering failed
- Allocator error if allocation failed
*/
font_render_string :: proc(self:^font, _str:string, _renderOpt:font_render_opt, allocator := context.allocator) -> (res:^geometry.raw_shape, err:geometry.shape_error = nil) {
	if self == nil do trace.panic_log("font_render_string: font is nil")

    vertList := make([dynamic]geometry.shape_vertex2d, context.temp_allocator)
    defer delete(vertList)

    indList := make([dynamic]u32, context.temp_allocator)
    defer delete(indList)

    _, rect := _font_render_string(auto_cast self, _str, _renderOpt, &vertList, &indList) or_return
    
    res = new (geometry.raw_shape, allocator) or_return
    res^ = {
        rect = rect,
    }
	res.vertices = mem.make_non_zeroed_slice([]geometry.shape_vertex2d, len(vertList), allocator) or_return
    runtime.mem_copy_non_overlapping(raw_data(res.vertices), &vertList[0], len(vertList) * size_of(geometry.shape_vertex2d))
    res.indices = mem.make_non_zeroed_slice([]u32, len(indList), allocator) or_return
    runtime.mem_copy_non_overlapping(raw_data(res.indices), &indList[0], len(indList) * size_of(u32))
    return
}