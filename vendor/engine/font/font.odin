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
import "vendor:engine/geometry"
import "vendor:freetype"
import "../"

// ============================================================================
// Type Definitions
// ============================================================================


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

// ============================================================================
// Font Rendering Options
// ============================================================================

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

// ============================================================================
// Global Variables
// ============================================================================

@(private) freetype_lib:freetype.Library = nil

// ============================================================================
// FreeType Initialization
// ============================================================================

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

// ============================================================================
// Type Aliases
// ============================================================================

freetype_err :: freetype.Error

// ============================================================================
// Font Management
// ============================================================================

font_init :: proc(_fontData:[]byte, #any_int _faceIdx:int = 0, allocator:mem.Allocator = context.allocator) -> (font : ^font = nil, err : freetype_err = .Ok)  {
    font_ := mem.new_non_zeroed(font_t, allocator)
    defer if err != .Ok do free(font_, allocator)

    font_.scale = SCALE_DEFAULT
    font_.mutex = {}

    font_.char_array = make_map( map[FONT_KEY]char_data, allocator )
    defer if err != .Ok do delete(font_.char_array)

    if freetype_lib == nil do _init_freetype()

    err = freetype.new_memory_face(freetype_lib, raw_data(_fontData), auto_cast len(_fontData), auto_cast _faceIdx, &font_.face)
    if err != .Ok {
        return
    }

    defer if err != .Ok {
        err = freetype.done_face(font_.face)
    }  

    err = freetype.set_char_size(font_.face, 0, 16 * 256 * 64, 0, 0)
    if err != .Ok do return

    font_.allocator = allocator
    font = auto_cast font_
    return
}

font_deinit :: proc(self:^font) -> (err : freetype.Error = .Ok) {
    self_:^font_t = auto_cast self
    sync.mutex_lock(&self_.mutex)

    err = freetype.done_face(self_.face)
    if err != .Ok do trace.panic_log(err)

    for key,value in self_.char_array {
        geometry.raw_shape_free(value.raw_shape, self_.allocator)
    }
    delete(self_.char_array)
    sync.mutex_unlock(&self_.mutex)
    free(self_, self_.allocator)

    return
}

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
allocator : runtime.Allocator) -> (rect:linalg.RectF, err:geometry.shape_error = .None) {
    i : int = 0
    opt := _renderOpt.opt
    rectT : linalg.RectF
    rect = linalg.Rect_Init(f32(0.0), 0.0, 0.0, 0.0)

    for r in _renderOpt.ranges {
        opt.scale = _renderOpt.opt.scale * r.scale
        opt.color = r.color

        if r.len == 0 || i + auto_cast r.len >= len(_str) {
            _, rectT = _font_render_string(auto_cast r.font, _str[i:], opt, vertList, indList, allocator) or_return
            rect = linalg.Rect_Or(rect, rectT)
            break;
        } else {
            opt.offset, rectT = _font_render_string(auto_cast r.font, _str[i:i + auto_cast r.len], opt, vertList, indList, allocator) or_return
            rect = linalg.Rect_Or(rect, rectT)
            i += auto_cast r.len
        }
    }
    return
}

@(private="file") _font_render_string :: proc(self:^font_t,
    _str:string,
    _renderOpt:font_render_opt,
    _vertArr:^[dynamic]geometry.shape_vertex2d,
    _indArr:^[dynamic]u32,
    allocator : runtime.Allocator) -> (pt:linalg.PointF, rect:linalg.RectF, err:geometry.shape_error = .None) {

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
             _renderOpt.color, _renderOpt.stroke_color, _renderOpt.thickness, allocator) or_return
        
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
    rect = linalg.Rect_Init_LTRB(minP.x, maxP.x, maxP.y, minP.y)

    subX :f32 = rect.pos.x + rect.size.x / 2.0
    subY :f32 = -rect.pos.y + rect.size.y / 2.0//remove rect.pos xy
    for &v in _vertArr^ {//move to center
        v.pos.x -= subX
        v.pos.y += subY
    }
    rect = linalg.Rect_Move(rect, linalg.PointF{-subX, subY})

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
    allocator : runtime.Allocator) -> (shapeErr:geometry.shape_error = .None) {
    ok := FONT_KEY{_char, thickness} in self.char_array
    charD : ^char_data

    FTMoveTo :: proc "c" (to: ^freetype.Vector, user: rawptr) -> c.int {
        data : ^font_user_data = auto_cast user
        data.pen = linalg.PointF{f32(to.x) / (64 * data.scale), f32(to.y) / (64 * data.scale)}

        if data.idx > 0 {
            data.polygon.nPolys[data.nPoly] = data.nPolyLen
            data.nPoly += 1
            data.polygon.nTypes[data.nTypes] = data.nTypesLen
            data.nTypes += 1
            data.nPolyLen = 0
            data.nTypesLen = 0
        }
        return 0
    }
    FTLineTo :: proc "c" (to: ^freetype.Vector, user: rawptr) -> c.int {
        data : ^font_user_data = auto_cast user
        end := linalg.PointF{f32(to.x) / (64 * data.scale), f32(to.y) / (64 * data.scale)}
    
        data.polygon.poly[data.idx] = data.pen
        data.polygon.types[data.typeIdx] = .Line
        data.pen = end
        data.idx += 1
        data.nPolyLen += 1
        data.typeIdx += 1
        data.nTypesLen += 1
        return 0
    }
    FTConicTo :: proc "c" (control: ^freetype.Vector, to: ^freetype.Vector, user: rawptr) -> c.int {
        data : ^font_user_data = auto_cast user
        ctl := linalg.PointF{f32(control.x) / (64 * data.scale), f32(control.y) / (64 * data.scale)}
        end := linalg.PointF{f32(to.x) / (64 * data.scale), f32(to.y) / (64 * data.scale)}
    
        data.polygon.poly[data.idx] = data.pen
        data.polygon.poly[data.idx+1] = ctl
        data.polygon.types[data.typeIdx] = .Quadratic
        data.pen = end
        data.idx += 2
        data.nPolyLen += 2
        data.typeIdx += 1
        data.nTypesLen += 1
        return 0
    }
    FTCubicTo :: proc "c" (control0, control1, to: ^freetype.Vector, user: rawptr) -> c.int {
        data : ^font_user_data = auto_cast user
        ctl0 := linalg.PointF{f32(control0.x) / (64 * data.scale), f32(control0.y) / (64 * data.scale)}
        ctl1 := linalg.PointF{f32(control1.x) / (64 * data.scale), f32(control1.y) / (64 * data.scale)}
        end := linalg.PointF{f32(to.x) / (64 * data.scale), f32(to.y) / (64 * data.scale)}
    
        data.polygon.poly[data.idx] = data.pen
        data.polygon.poly[data.idx+1] = ctl0
        data.polygon.poly[data.idx+2] = ctl1
        data.polygon.types[data.typeIdx] = .Unknown
        data.pen = end
        data.idx += 3
        data.nPolyLen += 3
        data.typeIdx += 1
        data.nTypesLen += 1
        return 0
    }
    font_user_data :: struct {
        pen : linalg.PointF,
        polygon : ^geometry.shapes,
        idx : u32,
        nPoly : u32,
        nPolyLen : u32,
        nTypes : u32,
        nTypesLen : u32,
        typeIdx : u32,
        scale : f32,
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
        
            poly : geometry.shapes = {
                nPolys = mem.make_non_zeroed([]u32, self.face.glyph.outline.n_contours, context.temp_allocator),//갯수는 후에 RESIZE 처리
                nTypes = mem.make_non_zeroed([]u32, self.face.glyph.outline.n_contours, context.temp_allocator),
                types = mem.make_non_zeroed([]geometry.curve_type, self.face.glyph.outline.n_points * 3, context.temp_allocator),
                poly = mem.make_non_zeroed([]linalg.PointF, self.face.glyph.outline.n_points * 3, context.temp_allocator),
            }
            if thickness > 0.0 {
                poly.strokeColors = mem.make_non_zeroed([]linalg.Point3DwF, self.face.glyph.outline.n_contours, context.temp_allocator)
                poly.thickness = mem.make_non_zeroed([]f32, self.face.glyph.outline.n_contours, context.temp_allocator)
            }
            if color != nil {
                poly.colors = mem.make_non_zeroed([]linalg.Point3DwF, self.face.glyph.outline.n_contours, context.temp_allocator)
            }

            defer {
                delete(poly.nPolys, context.temp_allocator)
                delete(poly.nTypes, context.temp_allocator)
                delete(poly.types, context.temp_allocator)
                delete(poly.poly, context.temp_allocator)
                if poly.strokeColors != nil {
                    delete(poly.strokeColors, context.temp_allocator)
                    delete(poly.thickness, context.temp_allocator)
                }
                if poly.colors != nil {
                    delete(poly.colors, context.temp_allocator)
                }
            }

            data : font_user_data = {
                polygon = &poly,
                idx = 0,
                typeIdx = 0,
                nPolyLen = 0,
                nTypesLen = 0,
                scale = self.scale,
            }
        
            err = freetype.outline_decompose(&self.face.glyph.outline, &funcs, &data)
            if err != .Ok do trace.panic_log(err)

            charData : char_data
            if data.idx == 0 {
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
               
                poly.nPolys[data.nPoly] = data.nPolyLen
                poly.nTypes[data.nTypes] = data.nTypesLen
                poly.poly = mem.resize_non_zeroed_slice(poly.poly, data.idx, context.temp_allocator)
                poly.types = mem.resize_non_zeroed_slice(poly.types, data.typeIdx, context.temp_allocator)
                if thickness > 0.0 {
                    poly.strokeColors = mem.resize_non_zeroed_slice(poly.strokeColors, data.nPoly + 1, context.temp_allocator)
                    poly.thickness = mem.resize_non_zeroed_slice(poly.thickness, data.nPoly + 1, context.temp_allocator)
                     for &c in poly.strokeColors {
                        c = linalg.Point3DwF{0,0,0,1}//?no matter
                    }
                    for &t in poly.thickness {
                        t = thickness
                    }
                }
                if color != nil {
                    poly.colors = mem.resize_non_zeroed_slice(poly.colors, data.nPoly + 1, context.temp_allocator)
                    for &c in poly.colors {
                        c = linalg.Point3DwF{0,0,0,2}//?no matter but stroke 와 구분한다.
                    }
                }

                rawP : ^geometry.raw_shape
                rawP , shapeErr = geometry.shapes_compute_polygon(&poly)//높은 부하 작업 High load operations
                if shapeErr != .None do return

                defer if shapeErr != .None {
                    geometry.raw_shape_free(rawP)
                }
                if len(rawP.vertices) > 0 {
                    maxP :linalg.PointF = {min(f32), min(f32)}
                    minP :linalg.PointF = {max(f32), max(f32)}

                    for v in rawP.vertices {
                        minP = math.min_array(minP, v.pos)
                        maxP = math.max_array(maxP, v.pos)
                    }
                    rawP.rect = linalg.Rect_Init_LTRB(minP.x, maxP.x, maxP.y, minP.y)
                }

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
    ww := charD.raw_shape == nil ? charD.advance_x : charD.raw_shape.rect.size.x + charD.raw_shape.rect.pos.x
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

font_render_string2 :: proc(_str:string, _renderOpt:font_render_opt2, allocator := context.allocator) -> (res:^geometry.raw_shape, err:geometry.shape_error = nil)  {
    vertList := make([dynamic]geometry.shape_vertex2d, allocator)
    indList := make([dynamic]u32, allocator)

    _font_render_string2(_str, _renderOpt, &vertList, &indList, allocator) or_return
    shrink(&vertList)
    shrink(&indList)
    res = new (geometry.raw_shape, allocator)
    res^ = {
        vertices = vertList[:],
        indices = indList[:],
    }
    return
}


font_render_string :: proc(self:^font, _str:string, _renderOpt:font_render_opt, allocator := context.allocator) -> (res:^geometry.raw_shape, err:geometry.shape_error = nil) {
    vertList := make([dynamic]geometry.shape_vertex2d, allocator)
    indList := make([dynamic]u32, allocator)

    _, rect := _font_render_string(auto_cast self, _str, _renderOpt, &vertList, &indList, allocator) or_return

    shrink(&vertList)
    shrink(&indList)
    res = new (geometry.raw_shape, allocator)
    res^ = {
        vertices = vertList[:],
        indices = indList[:],
        rect = rect,
    }
    return
}