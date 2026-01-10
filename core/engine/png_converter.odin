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


/*
PNG image converter structure

Stores the loaded image and allocator for memory management
*/
png_converter :: struct {
    img : ^image.Image,
    allocator:runtime.Allocator,
}


/*
Gets the width of the loaded PNG image

Inputs:
- self: Pointer to the PNG converter

Returns:
- The width of the image in pixels, or 0 if no image is loaded
*/
png_converter_width :: proc "contextless" (self:^png_converter) -> u32 {
    if self.img != nil {
        return u32(self.img.width)
    }
    return 0
}

/*
Gets the height of the loaded PNG image

Inputs:
- self: Pointer to the PNG converter

Returns:
- The height of the image in pixels, or 0 if no image is loaded
*/
png_converter_height :: proc "contextless" (self:^png_converter) -> u32 {
    if self.img != nil {
        return u32(self.img.height)
    }
    return 0
}

/*
Gets the size in bytes of the loaded PNG image

Inputs:
- self: Pointer to the PNG converter

Returns:
- The size of the image data in bytes, or 0 if no image is loaded
*/
png_converter_size :: proc "contextless" (self:^png_converter) -> u32 {
    if self.img != nil {
        return u32((self.img.depth >> 3) * self.img.width * self.img.height)
    }
    return 0
}

png_converter_deinit :: image_converter_deinit

/*
Loads a PNG image from byte data

Inputs:
- self: Pointer to the PNG converter
- data: The PNG image data as bytes
- out_fmt: The desired output color format
- allocator: The allocator to use (default: context.allocator)

Returns:
- The decoded image data as bytes
- An error if loading failed

Example:
	data, err := png_converter_load(&converter, file_data, .RGBA)
*/
png_converter_load :: proc (self:^png_converter, data:[]byte, out_fmt:color_fmt, allocator := context.allocator) -> ([]byte, png_error) {
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

png_error :: union #shared_nil {
    image.Error,
    os2.Error,
}

/*
Loads a PNG image from a file

Inputs:
- self: Pointer to the PNG converter
- file_path: Path to the PNG image file
- out_fmt: The desired output color format
- allocator: The allocator to use (default: context.allocator)

Returns:
- The decoded image data as bytes
- An error if loading failed

Example:
	data, err := png_converter_load_file(&converter, "image.png", .RGBA)
*/
png_converter_load_file :: proc (self:^png_converter, file_path:string, out_fmt:color_fmt, allocator := context.allocator) -> ([]byte, png_error) {
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