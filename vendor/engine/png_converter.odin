package engine

import "core:mem"
import "core:debug/trace"
import "base:intrinsics"
import "base:runtime"
import "core:image/png"
import "core:image"
import "core:bytes"
import "core:os/os2"
import "core:sys/android"


png_converter :: struct {
    img : ^image.Image,
    allocator:runtime.Allocator,
}


png_converter_width :: proc "contextless" (self:^png_converter) -> int {
    if self.img != nil {
        return self.img.width
    }
    return -1
}

png_converter_height :: proc "contextless" (self:^png_converter) -> int {
    if self.img != nil {
        return self.img.height
    }
    return -1
}

png_converter_size :: proc "contextless" (self:^png_converter) -> int {
    if self.img != nil {
        return (self.img.depth >> 3) * self.img.width * self.img.height
    }
    return -1
}

png_converter_deinit :: image_converter_deinit

png_converter_load :: proc (self:^png_converter, data:[]byte, out_fmt:color_fmt, allocator := context.allocator) -> ([]byte, Png_Error) {
    png_converter_deinit(self)

    err : image.Error = nil
    #partial switch out_fmt {
        case .RGBA, .RGBA16: self.img, err = png.load_from_bytes(data, png.Options{.alpha_add_if_missing}, allocator = allocator)
        case .RGB, .RGB16: self.img, err = png.load_from_bytes(data, png.Options{.alpha_drop_if_present}, allocator = allocator)
        case .Unknown: self.img, err = png.load_from_bytes(data, allocator = allocator)
        case : trace.panic_log("unsupport option")
    }
    
    self.allocator = allocator

    if err != nil {
        return nil, err
    }
    
    out_data := bytes.buffer_to_bytes(&self.img.pixels)
  
    return out_data, err
}

Png_Error :: union #shared_nil {
    image.Error,
    os2.Error,
}

png_converter_load_file :: proc (self:^png_converter, file_path:string, out_fmt:color_fmt, allocator := context.allocator) -> ([]byte, Png_Error) {
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

    return png_converter_load(self, imgFileData, out_fmt, allocator)
}