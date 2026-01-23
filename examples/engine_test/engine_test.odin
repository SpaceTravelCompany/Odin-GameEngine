package engine_test

import "core:fmt"
import "core:mem"
import "core:thread"
import "core:math"
import "core:math/rand"
import "core:math/linalg"
import "core:reflect"
import "base:runtime"
import "core:os/os2"
import "core:sys/android"
import "core:engine"
import "core:image/qoi"
import "core:engine/font"
import "core:engine/sound"
import "core:engine/shape"
import "core:engine/geometry"
import "core:engine/gui"
import "core:debug/trace"
import "vendor:svg"

is_android :: engine.is_android

renderCmd : ^engine.layer
scene: [dynamic]^engine.iobject

shapeSrc: shape.shape_src
texture:engine.texture

CANVAS_W :f32: 1280
CANVAS_H :f32: 720

ft:^font.font

bgSndSrc : ^sound.sound_src
bgSnd : ^sound.sound

bgSndFileData:[]u8

GUI_Image_Vtable: engine.iobject_vtable = {
    size = auto_cast GUI_Image_Size,
}
GUI_Image_Init :: proc(self:^GUI_Image, src:^engine.texture,
colorTransform:^engine.color_transform = nil) {
    engine.image_init2(auto_cast self, GUI_Image, src, colorTransform,&GUI_Image_Vtable)
    gui.gui_component_size(self, &self.com)
}

GUI_Image_Size :: proc(self:^GUI_Image) {
    gui.gui_component_size(self, &self.com)
}


GUI_Image :: struct {
    using _:engine.image,
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

svg_shape_src : shape.shape_src
init_svg :: proc() {
    svg_parser, err := svg.init_parse(github_mark_svg, context.temp_allocator)
    if err != nil {
        trace.panic_log(err)
    }
    defer svg.deinit(&svg_parser)

	geometry.poly_transform_matrix(&svg_parser.shapes, engine.srtc_2d_matrix(
		t = {0,0,0},
		cp = {-8,8},
		s = {30,30},
		r = 0.5,
	))

    svg_shape := new(shape.shape)
    shape_err := shape.shape_src_init(&svg_shape_src, &svg_parser.shapes)
    if shape_err != nil {
        trace.panic_log(shape_err)
    }

    shape.shape_init(svg_shape, shape.shape, &svg_shape_src, 
        {0,0,0}, )
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
        fontFileData, fontFileReadErr = android.asset_read_file("omyu pretty.ttf", context.temp_allocator)
        if fontFileReadErr != .None {
            trace.panic_log(fontFileReadErr)
        }
    } else {
        fontFileReadErr :os2.Error
        fontFileData, fontFileReadErr = os2.read_entire_file_from_path("res/omyu pretty.ttf", context.temp_allocator)
        if fontFileReadErr != nil {
            trace.panic_log(fontFileReadErr)
        }
    }

    freeTypeErr : font.freetype_err
    ft, freeTypeErr = font.font_init(fontFileData, 0)
    if freeTypeErr != .Ok {
        trace.panic_log(freeTypeErr)
    }
	
    renderOpt := font.font_render_opt{
        color = linalg.point3dw{1,1,1,1},
        flag = .GPU,
        scale = linalg.point{3,3},
    }

    rawText, shapeErr := font.font_render_string(ft, "안녕", renderOpt, context.allocator)
    if shapeErr != nil {
        trace.panic_log(shapeErr)
    }
    defer free(rawText)
    //!DO NOT geometry.raw_shape_free, auto delete vertex and index data after shape_src_init_raw completed
    //!only delete raw single pointer

    shape.shape_src_init_raw(&shapeSrc, rawText, allocator = context.allocator)

    shape.shape_init(shape_obj, shape.shape, &shapeSrc, {-0.0, 0, 10}, math.to_radians_f32(45.0), {3, 3},
    pivot = {0.0, 0.0})

    engine.layer_add_object(renderCmd, shape_obj)

    //Sound Test
    when is_android {
        sndFileReadErr : android.AssetFileError
        bgSndFileData, sndFileReadErr = android.asset_read_file("BG.opus", context.allocator)
        if sndFileReadErr != .None {
            trace.panic_log(sndFileReadErr)
        }
    } else {
        sndFileReadErr :os2.Error
        bgSndFileData, sndFileReadErr = os2.read_entire_file_from_path("res/BG.opus", context.allocator)
        if sndFileReadErr != nil {
            trace.panic_log(sndFileReadErr)
        }
    }

    bgSndSrc, _ = sound.sound_src_decode_sound_memory(bgSndFileData)
    bgSnd, _ = sound.sound_src_play_sound_memory(bgSndSrc, 0.2, true)

    //Input Test
    generalInputFn :: proc(state:engine.general_input_state) {//current android only support
        fmt.printfln("GENERAL [%v]", state.handle)
        fmt.printfln("buttons:%s%s%s%s %s %s",
            state.buttons.a ? "A" : " ",
            state.buttons.b ? "B" : " ",
            state.buttons.x ? "X" : " ",
            state.buttons.y ? "Y" : " ",
            state.buttons.back ? "BACK" : " ",
            state.buttons.start ? "START" : " ")

        fmt.printfln("DPAD:%s%s%s%s Shoulders:%s%s %s%s",
            state.buttons.dpad_up ? "U" : " ",
            state.buttons.dpad_down ? "D" : " ",
            state.buttons.dpad_left ? "L" : " ",
            state.buttons.dpad_right ? "R" : " ",
            state.buttons.left_shoulder ? "L" : " ",
            state.buttons.right_shoulder ? "R" : " ",
            state.buttons.volume_up ? "+" : " ",
            state.buttons.volume_down ? "-" : " ")

        fmt.printfln("Thumb:%s%s LeftThumb:(%f,%f) RightThumb:(%f,%f)",
            state.buttons.left_thumb ? "L" : " ",
            state.buttons.right_thumb ? "R" : " ",
            state.left_thumb.x,
            state.left_thumb.y,
            state.right_thumb.x,
            state.right_thumb.y)

        fmt.printfln("Trigger:(%f,%f)",
            state.left_trigger,
            state.right_trigger)
    }
    engine.general_input_callback = generalInputFn

    //Image Test
    qoiD :^qoi.qoi_converter = new(qoi.qoi_converter)

    imgData, errCode := qoi.qoi_converter_load(qoiD, panda_img, .RGBA)
    if errCode != nil {
        trace.panic_log(errCode)
    }

    engine.texture_init(&texture,
         u32(qoi.qoi_converter_width(qoiD)), u32(qoi.qoi_converter_height(qoiD)),
          imgData, runtime.Allocator{
            procedure= panda_img_allocator_proc,
            data= auto_cast qoiD,
          })

    img: ^GUI_Image = new(GUI_Image)
    img.com.gui_scale = {0.7,0.7}
    img.com.gui_rotation = math.to_radians_f32(45.0)
    img.com.gui_align_x = .left
    img.com.gui_pos.x = 200.0

	GUI_Image_Init(img, &texture)

    fmt.printfln("texture width: %d, height: %d", qoi.qoi_converter_width(qoiD), qoi.qoi_converter_height(qoiD))
    

    engine.layer_add_object(renderCmd, auto_cast img)

    //Show
    engine.layer_show(renderCmd)
}
Update ::proc() {
}

Destroy ::proc() {
    shape.shape_src_deinit(&shapeSrc)
    engine.texture_deinit(&texture)
    len := engine.layer_get_object_len(renderCmd)
    for i in 0..<len {
        obj := engine.layer_get_object(renderCmd, i)
        engine.iobject_deinit(obj)
        free(obj)
    }
    engine.layer_deinit(renderCmd)

	delete(scene)

	font.font_deinit(ft)
	shape.shape_src_deinit(&svg_shape_src)

    sound.sound_src_deinit(bgSndSrc)
    delete(bgSndFileData)
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


