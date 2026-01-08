package engine_test

import "core:fmt"
import "core:mem"
import "core:thread"
import "core:math"
import "core:math/rand"
import "core:math/linalg"
import "core:reflect"
import "core:os/os2"
import "core:sys/android"
import "core:engine"
import "core:engine/font"
import "core:engine/sound"
import "core:engine/geometry"
import "core:engine/gui"
import "core:debug/trace"

is_android :: engine.is_android// TODO ANDROID SUPPORT

renderCmd : ^engine.render_cmd

shapeSrc: engine.shape_src
texture:engine.texture

camera: engine.camera
proj: engine.projection

CANVAS_W :f32: 1280
CANVAS_H :f32: 720

ft:^font.font

bgSndSrc : ^sound.sound_src
bgSnd : ^sound.sound

bgSndFileData:[]u8

GUI_Image_Init :: proc(self:^GUI_Image, src:^engine.texture,
camera:^engine.camera, projection:^engine.projection,
colorTransform:^engine.color_transform = nil) {
    engine.image_init2(auto_cast self, GUI_Image, src, camera, projection, colorTransform)

    gui.gui_component_size(self, &self.com)
}


GUI_Image :: struct {
    using _:engine.image,
    com:gui.gui_component,
}

panda_img : []u8 = #load("res/panda.qoi")

Init ::proc() {
    renderCmd = engine.render_cmd_init()

    engine.camera_init(&camera, )
    engine.projection_init_matrix_ortho_window(&proj, CANVAS_W, CANVAS_H)

    //Font Test
    shape: ^engine.shape = new(engine.shape, engine.def_allocator())

    fontFileData:[]u8
    defer delete(fontFileData, context.temp_allocator)

    // when is_android {
    //     fontFileReadErr : android.asset_file_error
    //     fontFileData, fontFileReadErr = android.asset_read_file("omyu pretty.ttf", context.temp_allocator)
    //     if fontFileReadErr != .None {
    //         trace.panic_log(fontFileReadErr)
    //     }
    // } else {
        fontFileReadErr :os2.Error
        fontFileData, fontFileReadErr = os2.read_entire_file_from_path("res/omyu pretty.ttf", context.temp_allocator)
        if fontFileReadErr != nil {
            trace.panic_log(fontFileReadErr)
        }
    //}

    freeTypeErr : font.freetype_err
    ft, freeTypeErr = font.font_init(fontFileData, 0)
    if freeTypeErr != .Ok {
        trace.panic_log(freeTypeErr)
    }

    //font.Font_SetScale(ft, 2)

    renderOpt := font.font_render_opt{
        color = linalg.Point3DwF{1,1,1,1},
        flag = .GPU,
        scale = linalg.PointF{3,3},
    }

    rawText, shapeErr := font.font_render_string(ft, "안녕", renderOpt, context.temp_allocator)
    if shapeErr != .None {
        trace.panic_log(shapeErr)
    }
    defer geometry.raw_shape_free(rawText, context.temp_allocator)

    engine.shape_src_init_raw(&shapeSrc, rawText)

    engine.shape_init(shape, engine.shape, &shapeSrc, {-0.0, 0, 10}, &camera, &proj, math.to_radians_f32(45.0), {3, 3},
    pivot = {0.0, 0.0})

    engine.render_cmd_add_object(renderCmd, shape)

    //Sound Test
    // when is_android {
    //     sndFileReadErr : android.asset_file_error
    //     bgSndFileData, sndFileReadErr = android.asset_read_file("BG.opus", context.allocator)
    //     if sndFileReadErr != .None {
    //         trace.panic_log(sndFileReadErr)
    //     }
    // } else {
        sndFileReadErr :os2.Error
        bgSndFileData, sndFileReadErr = os2.read_entire_file_from_path("res/BG.opus", context.allocator)
        if sndFileReadErr != nil {
            trace.panic_log(sndFileReadErr)
        }
    //}

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
    //

    //Image Test
    qoiD :engine.qoi_converter
    defer engine.qoi_converter_deinit(&qoiD)

    //imgData, errCode := engine.image_converter_load_file(qoiD, "res/panda.qoi", .RGBA)
    imgData, errCode := engine.image_converter_load(&qoiD, panda_img, .RGBA)
    if errCode != nil {
        trace.panic_log(errCode)
    }

    engine.texture_init(&texture, u32(engine.image_converter_width(&qoiD)), u32(engine.image_converter_height(&qoiD)), imgData)

    img: ^GUI_Image = new(GUI_Image, engine.def_allocator())
    img.com.gui_scale = {0.7,0.7}
    img.com.gui_rotation = math.to_radians_f32(45.0)
    img.com.gui_align_x = .left
    img.com.gui_pos.x = 200.0

    fmt.printfln("texture width: %d, height: %d", engine.image_converter_width(&qoiD), engine.image_converter_height(&qoiD))
    
    GUI_Image_Init(img, &texture,  &camera, &proj)
    

    engine.render_cmd_add_object(renderCmd, auto_cast img)

    //Show
    engine.render_cmd_show(renderCmd)

    // WaitThread :: proc(data:rawptr) {
    //     engine.GraphicsWaitAllOps()
    // }
    // thread.create_and_start_with_data(qoiD, WaitThread, self_cleanup = true)

    // engine.GraphicsWaitAllOps()

    // engine.image_converter_deinit(qoiD)
}
Update ::proc() {
}
Size :: proc() {
    engine.projection_update_ortho_window(&proj, CANVAS_W, CANVAS_H)
    
    gui_img := (^GUI_Image)(engine.render_cmd_get_object(renderCmd, 1))

    gui.gui_component_size(gui_img, &gui_img.com)
}
Destroy ::proc() {
    engine.shape_src_deinit(&shapeSrc)
    engine.texture_deinit(&texture)
    len := engine.render_cmd_get_object_len(renderCmd)
    for i in 0..<len {
        obj := engine.render_cmd_get_object(renderCmd, i)
        engine.iobject_deinit(obj)
        free(obj, engine.def_allocator())
    }
    engine.render_cmd_deinit(renderCmd)

    engine.camera_deinit(&camera)
    engine.projection_deinit(&proj)

    sound.sound_src_deinit(bgSndSrc)
    delete(bgSndFileData)
}


main :: proc() {
    engine.init = Init
    engine.update = Update
    engine.destroy = Destroy
    engine.size = Size
    engine.engine_main(window_width = int(CANVAS_W), window_height = int(CANVAS_H))
}


