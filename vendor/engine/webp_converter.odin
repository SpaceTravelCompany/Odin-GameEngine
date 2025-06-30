package engine

import "core:mem"
import "core:debug/trace"
import "core:os/os2"
import "core:sys/android"
import "base:intrinsics"
import "base:runtime"
import "vendor:webp"

@private webp_config :: union {
    webp.WebPDecoderConfig,
    webp.WebPAnimDecoderOptions,
}

@private webp_converter_in :: struct {
    anim_dec:^webp.WebPAnimDecoder,
    anim_info:webp.WebPAnimInfo,
    out_fmt:color_fmt,
    config:webp_config,
    allocator:runtime.Allocator,
}
webp_converter :: struct {
    __in : webp_converter_in,
}

webp_converter_width :: proc "contextless" (self:^webp_converter) -> int {
    if self.__in.config != nil {
        switch &t in self.__in.config {
        case webp.WebPDecoderConfig:
            return auto_cast t.input.width
        case webp.WebPAnimDecoderOptions:
            return auto_cast self.__in.anim_info.canvas_width
        }
    }
    return -1
}

webp_converter_height :: proc "contextless" (self:^webp_converter) -> int {
    if self.__in.config != nil {
        switch &t in self.__in.config {
        case webp.WebPDecoderConfig:
            return auto_cast t.input.height
        case webp.WebPAnimDecoderOptions:
            return auto_cast self.__in.anim_info.canvas_height
        }
    }
    return -1
}

webp_converter_size :: proc "contextless" (self:^webp_converter) -> int {
    if self.__in.config != nil {
        switch &t in self.__in.config {
        case webp.WebPDecoderConfig:
            return int(t.input.height * t.input.width) * (color_fmt_bit(self.__in.out_fmt) >> 3)
        case webp.WebPAnimDecoderOptions:
            return int(self.__in.anim_info.canvas_height * self.__in.anim_info.canvas_width * self.__in.anim_info.frame_count) * (color_fmt_bit(self.__in.out_fmt) >> 3)
        }
    }
    return -1
}

webp_converter_frame_cnt :: proc "contextless" (self:^webp_converter) -> int {
    if self.__in.config != nil {
        switch &t in self.__in.config {
        case webp.WebPAnimDecoderOptions:
            return auto_cast self.__in.anim_info.frame_count
        case webp.WebPDecoderConfig:
            return 1
        }
    }
    return -1
}

webp_converter_deinit :: proc (self:^webp_converter) {
    if self.__in.config != nil {
        switch &t in self.__in.config {
        case webp.WebPDecoderConfig:
            webp.WebPFreeDecBuffer(&(t.output))
            self.__in.config = nil
        case webp.WebPAnimDecoderOptions:
            webp.WebPAnimDecoderDelete(self.__in.anim_dec)
            self.__in.config = nil
        }
    }
}

webp_converter_load :: proc (self:^webp_converter, data:[]byte, out_fmt:color_fmt, allocator := context.allocator) -> ([]byte, WebP_Error) {
    webp_converter_deinit(self)

    errCode :WebP_Error = nil
    animOp:^webp.WebPAnimDecoderOptions

    anim_load: {   
        self.__in.config = webp.WebPAnimDecoderOptions{}
        webp.WebPAnimDecoderOptionsInit(&self.__in.config.(webp.WebPAnimDecoderOptions))

        wData := webp.WebPData{
            bytes = &data[0],
            size = len(data),
        }
        animOp = &self.__in.config.(webp.WebPAnimDecoderOptions)
        #partial switch out_fmt {
            case .RGBA : animOp.color_mode = webp.CSP_MODE.RGBA
            case .ARGB : animOp.color_mode = webp.CSP_MODE.ARGB
            case .BGRA : animOp.color_mode = webp.CSP_MODE.BGRA
            case .RGB : animOp.color_mode = webp.CSP_MODE.RGB
            case .BGR : animOp.color_mode = webp.CSP_MODE.BGR
            case : trace.panic_log("unsupports decode fmt : ", out_fmt)
        }

        self.__in.anim_dec = webp.WebPAnimDecoderNew(&wData, &self.__in.config.(webp.WebPAnimDecoderOptions))
        if self.__in.anim_dec == nil {
            errCode = .WebPAnimDecoderNew_Failed
            break anim_load
        }

        webp.WebPAnimDecoderGetInfo(self.__in.anim_dec, &self.__in.anim_info)
    }
    
    if errCode != nil {
        //try load static image mode
        self.__in.config = webp.WebPDecoderConfig{}
        webp.WebPInitDecoderConfig(&self.__in.config.(webp.WebPDecoderConfig))
        op := &self.__in.config.(webp.WebPDecoderConfig)
        op.options.no_fancy_upsampling = true
        errCode = webp.WebPGetFeatures(&data[0], len(data), &op.input)
        if errCode != webp.VP8StatusCode.OK {
            self.__in.config = nil
            return nil, errCode
        } else {
            errCode = nil
        }

        op.options.scaled_width = op.input.width
        op.options.scaled_height = op.input.height
        op.output.colorspace = animOp.color_mode
    }

    self.__in.out_fmt = out_fmt
    self.__in.allocator = allocator

    out_data := mem.make_non_zeroed_slice([]byte, webp_converter_size(self), allocator)

    bit := color_fmt_bit(self.__in.out_fmt) >> 3

    switch &t in self.__in.config {
    case webp.WebPDecoderConfig:
        t.output.u.RGBA.rgba = &out_data[0]
        t.output.u.RGBA.stride = t.input.width * i32(bit)
        t.output.u.RGBA.size = uint(t.output.u.RGBA.stride * t.input.height)
        t.output.is_external_memory = 1

        errCode = webp.WebPDecode(&data[0], len(data), &t)
        if errCode != webp.VP8StatusCode.OK {
            delete(out_data, allocator)
            return nil, errCode
        } else {
            errCode = nil
        }
    case webp.WebPAnimDecoderOptions:
        idx := 0

        frame_size := int(self.__in.anim_info.canvas_width * self.__in.anim_info.canvas_height) * bit

        for 0 < webp.WebPAnimDecoderHasMoreFrames(self.__in.anim_dec) {
            timestamp : i32
            buf : [^]u8

            if 0 == webp.WebPAnimDecoderGetNext(self.__in.anim_dec, &buf, &timestamp) {
                delete(out_data, allocator)
                return nil, .WebPAnimDecoderGetNext_Failed
            }
            intrinsics.mem_copy_non_overlapping(&out_data[idx], buf, frame_size)

            idx += frame_size
        }
    }

    return out_data, errCode
}

WebP_Error_In ::enum {
    WebPAnimDecoderNew_Failed,
    WebPAnimDecoderGetNext_Failed,
}

WebP_Error :: union #shared_nil {
    WebP_Error_In,
    webp.VP8StatusCode,
    os2.Error,
}

webp_converter_load_file :: proc (self:^webp_converter, file_path:string, out_fmt:color_fmt, allocator := context.allocator) -> ([]byte, WebP_Error) {
    imgFileData:[]byte
    when is_android {
        imgFileReadErr : android.AssetFileError
        imgFileData, imgFileReadErr = android.asset_read_file(file_path, context.temp_allocator)
        if imgFileReadErr != .None {
            trace.panic_log(imgFileReadErr)
        }
    } else {
        imgFileReadErr:os2.Error
        imgFileData, imgFileReadErr = os2.read_entire_file_from_path(file_path, context.temp_allocator)
        if imgFileReadErr != nil {
            return nil, imgFileReadErr
        }
    }
    defer delete(imgFileData, context.temp_allocator)

    return webp_converter_load(self, imgFileData, out_fmt, allocator)
}