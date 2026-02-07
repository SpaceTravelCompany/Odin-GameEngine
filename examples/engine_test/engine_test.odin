package engine_test

import "core:fmt"
import "core:mem"
import "core:math"
import "core:math/linalg"
import "base:runtime"
import "core:os/os2"
import "core:sys/android"
import "core:engine"
import "core:image/qoi"
import "core:engine/font"
import "core:engine/sound"
import "core:engine/shape"
import "core:engine/sprite"
import "core:engine/geometry"
import "core:engine/gui"
import "vendor:svg"

is_android :: engine.is_android

renderCmd : ^engine.layer
scene: [dynamic]^engine.iobject

textShapes: geometry.shapes
texture:engine.texture

CANVAS_W :f32: 1280
CANVAS_H :f32: 720

ft:^font.font

bgSndSrc : ^sound.sound_src
bgSnd : ^sound.sound

bgSndFileData:[]u8

GUI_Sprite_Vtable: engine.iobject_vtable = {
    size = auto_cast GUI_Sprite_Size,
}
GUI_Sprite_Init :: proc(self:^GUI_Sprite, src:^engine.texture,
colorTransform:^engine.color_transform = nil) {
    sprite.sprite_init(auto_cast self, src, colorTransform, &GUI_Sprite_Vtable)
    gui.gui_component_size(self, &self.com)
	self.actual_type = typeid_of(GUI_Sprite)
}

GUI_Sprite_Size :: proc(self:^GUI_Sprite) {
    gui.gui_component_size(self, &self.com)
}


GUI_Sprite :: struct {
    using _:sprite.sprite,
    com:gui.gui_component,
}

panda_img : []u8 = #load("panda.qoi")
github_mark_svg : []u8 = #load("github-mark.svg")

panda_img_allocator_proc :: proc(allocator_data: rawptr, mode: runtime.Allocator_Mode,
                            size, alignment: int,
                            old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]byte, runtime.Allocator_Error) {
	#partial switch mode {
	case .Free:
		 qoiD :^qoi.qoi_converter = auto_cast allocator_data
		 qoi.qoi_converter_deinit(qoiD)
         free(qoiD, qoiD.allocator)
	}
	return nil, nil
}

svg_parser:svg.svg_parser
init_svg :: proc() {
	err : svg.SVG_ERROR
    svg_parser, err = svg.init_parse(github_mark_svg, context.allocator)
    if err != nil {
        fmt.panicf("svg.init_parse: %s", err)
    }

	geometry.poly_transform_matrix(&svg_parser.shapes, linalg.srtc_2d_matrix(
		t = {0,0,0},
		cp = {-8,8},
		s = {30,30},
		r = 0.5,
	))

    svg_shape := new(shape.shape)

    shape.shape_init(svg_shape, &svg_parser.shapes)
    engine.itransform_object_update_transform(svg_shape, {0,0,0}, 0.0, {1, 1})
    engine.layer_add_object(renderCmd, svg_shape)
}

Init ::proc() {
	scene = make([dynamic]^engine.iobject)
    renderCmd = engine.layer_init(&scene)

    engine.projection_update_ortho_window(engine.def_projection(), CANVAS_W, CANVAS_H)

    init_svg()

    //Font Test
    shape_obj: ^shape.shape = new(shape.shape)

    fontFileData:[]u8
    defer delete(fontFileData, context.temp_allocator)

    when is_android {
        fontFileReadErr : android.AssetFileError
        fontFileData, fontFileReadErr = android.asset_read_file("동그라미재단B.ttf", context.temp_allocator)
        if fontFileReadErr != .None {
            fmt.panicf("android.asset_read_file: %s", fontFileReadErr)
        }
    } else {
        fontFileReadErr :os2.Error
        fontFileData, fontFileReadErr = os2.read_entire_file_from_path("res/동그라미재단B.ttf", context.temp_allocator)
        if fontFileReadErr != nil {
            fmt.panicf("os2.read_entire_file_from_path: %s", fontFileReadErr)
        }
    }

    freeTypeErr : font.freetype_err
    ft, freeTypeErr = font.font_init(fontFileData, 0)
    if freeTypeErr != .Ok {
        fmt.panicf("font.font_init: %s", freeTypeErr)
    }
	
    renderOpt := font.font_render_opt{
        color = linalg.point3dw{1,1,1,1},
        scale = linalg.point{3,3},
    }
    rawText, shapeErr := font.font_render_string(ft, "안녕", renderOpt, context.allocator)
    if shapeErr != nil {
        fmt.panicf("font.font_render_string: %s", shapeErr)
    }
    textShapes = rawText

    shape.shape_init(shape_obj, &textShapes)
	engine.itransform_object_update_transform(shape_obj, {-0.0, 0, 10}, math.to_radians_f32(45.0), {3, 3})
    engine.layer_add_object(renderCmd, shape_obj)

    //Sound Test
    when is_android {
        sndFileReadErr : android.AssetFileError
        bgSndFileData, sndFileReadErr = android.asset_read_file("BG.opus", context.allocator)
        if sndFileReadErr != .None {
            fmt.panicf("android.asset_read_file: %s", sndFileReadErr)
        }
    } else {
        sndFileReadErr :os2.Error
        bgSndFileData, sndFileReadErr = os2.read_entire_file_from_path("res/BG.opus", context.allocator)
        if sndFileReadErr != nil {
            fmt.panicf("os2.read_entire_file_from_path: %s", sndFileReadErr)
        }
    }

    bgSndSrc, _ = sound.sound_src_decode_sound_memory(bgSndFileData)
    bgSnd, _ = sound.sound_src_play_sound_memory(bgSndSrc, 0.2, true)

    //Image Test
    qoiD :^qoi.qoi_converter = new(qoi.qoi_converter)

    imgData, errCode := qoi.qoi_converter_load(qoiD, panda_img, .RGBA)
    if errCode != nil {
        fmt.panicf("qoi.qoi_converter_load: %s", errCode)
    }

    engine.texture_init(&texture,
         u32(qoi.qoi_converter_width(qoiD)), u32(qoi.qoi_converter_height(qoiD)),
          imgData, runtime.Allocator{
            procedure = panda_img_allocator_proc,
            data = auto_cast qoiD,})

    img: ^GUI_Sprite = new(GUI_Sprite)
    img.com.gui_scale = {0.7,0.7}
    img.com.gui_rotation = math.to_radians_f32(45.0)
    img.com.gui_align_x = .left
    img.com.gui_pos.x = 200.0

	GUI_Sprite_Init(img, &texture)

    fmt.printfln("texture width: %d, height: %d", qoi.qoi_converter_width(qoiD), qoi.qoi_converter_height(qoiD))
    

    engine.layer_add_object(renderCmd, auto_cast img)

    //Show
    engine.layer_show(renderCmd)
}
Update ::proc() {
}

Destroy ::proc() {
    engine.texture_deinit(&texture)
    len := engine.layer_get_object_len(renderCmd)
    for i in 0..<len {
        obj := engine.layer_get_object(renderCmd, i)
        engine.iobject_deinit(obj)
        free(obj)
    }
    engine.layer_deinit(renderCmd)
	for n in textShapes.nodes {
		delete(n.lines, context.allocator)
	}
	delete(textShapes.nodes, context.allocator)

	delete(scene)

	font.font_deinit(ft)

    sound.sound_src_deinit(bgSndSrc)
    delete(bgSndFileData)

	svg.deinit(&svg_parser)
}

BREAKPOINT_ON_TRACKING_ALLOCATOR :: true

main :: proc() {
	when ODIN_DEBUG && !is_android {//!android not support tracking allocator now
		track_allocator: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track_allocator, context.allocator)
		context.allocator = mem.tracking_allocator(&track_allocator)
	}

    engine.init = Init
    engine.update = Update
    engine.destroy = Destroy
    engine.engine_main(window_width = int(CANVAS_W), window_height = int(CANVAS_H))

	when ODIN_DEBUG && !is_android {
		if track_allocator.backing.procedure != nil {
			when BREAKPOINT_ON_TRACKING_ALLOCATOR {
				breakP := false
			}

			if len(track_allocator.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track_allocator.allocation_map))
				for _, entry in track_allocator.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
				when BREAKPOINT_ON_TRACKING_ALLOCATOR {
					breakP = true
				}
			}
			if len(track_allocator.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track_allocator.bad_free_array))
				for entry in track_allocator.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
				when BREAKPOINT_ON_TRACKING_ALLOCATOR {
					breakP = true
				}
			}
			mem.tracking_allocator_destroy(&track_allocator)

			when BREAKPOINT_ON_TRACKING_ALLOCATOR {
				if breakP {
					runtime.debug_trap()
				}
			}
		}
	}
}


