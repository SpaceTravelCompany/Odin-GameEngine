package engine

import "core:mem"
import "core:debug/trace"
import "base:intrinsics"
import "base:runtime"
import "core:image/qoi"
import "core:image"
import "core:bytes"
import "core:os/os2"
import "core:sys/android"


qoi_converter :: struct {
    img : ^image.Image,
    allocator:runtime.Allocator,
}

qoi_converter_width :: proc "contextless" (self:^qoi_converter) -> u32 {
    if self.img != nil {
        return u32(self.img.width)
    }
    return 0
}

qoi_converter_height :: proc "contextless" (self:^qoi_converter) -> u32 {
    if self.img != nil {
        return u32(self.img.height)
    }
    return 0
}

qoi_converter_size :: proc "contextless" (self:^qoi_converter) -> u32 {
    if self.img != nil {
        return u32((self.img.depth >> 3) * self.img.width * self.img.height)
    }
    return 0
}

qoi_converter_deinit :: image_converter_deinit

qoi_converter_load :: proc (self:^qoi_converter, data:[]byte, out_fmt:color_fmt, allocator := context.allocator) -> ([]byte, Qoi_Error) {
    qoi_converter_deinit(self)

    err : image.Error = nil
    #partial switch out_fmt {
        case .RGBA, .RGBA16: self.img, err = qoi.load_from_bytes(data, qoi.Options{.alpha_add_if_missing}, allocator = allocator)
        case .RGB, .RGB16: self.img, err = qoi.load_from_bytes(data, qoi.Options{.alpha_drop_if_present}, allocator = allocator)
        case .Unknown: self.img, err = qoi.load_from_bytes(data, allocator = allocator)
        case : trace.panic_log("unsupport option")
    }
    
    self.allocator = allocator

    if err != nil {
        return nil, err
    }
    
    out_data := bytes.buffer_to_bytes(&self.img.pixels)
  
    return out_data, err
}


__Qoi_Error :: enum {
    None,
    Encode_Size_Mismatch,
}
Qoi_Error :: union #shared_nil {
    image.Error,
    os2.Error,
    __Qoi_Error,
}

qoi_converter_load_file :: proc (self:^qoi_converter, file_path:string, out_fmt:color_fmt, allocator := context.allocator) -> ([]byte, Qoi_Error) {
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

    return qoi_converter_load(self, imgFileData, out_fmt, allocator)
}

qoi_converter_encode :: proc (self:^qoi_converter, data:[]byte, in_fmt:color_fmt, width:int, height:int, allocator := context.allocator) -> ([]byte, Qoi_Error) {
    qoi_converter_deinit(self)

    ok:bool
    self.img = new(image.Image, context.temp_allocator)
    defer if !ok {
        free(self.img, context.temp_allocator)
        self.img = nil
    } else {
        self.img.pixels = {}
    }

    s := transmute(runtime.Raw_Slice)data

    #partial switch in_fmt {
        case .RGBA: 
            if s.len % 4 != 0 do return nil, .Encode_Size_Mismatch
            self.img^, ok = image.pixels_to_image((cast([^][4]byte)s.data)[:s.len / 4], width, height)
        case .RGBA16:
            if s.len % 8 != 0 do return nil, .Encode_Size_Mismatch
            self.img^, ok = image.pixels_to_image((cast([^][4]u16)s.data)[:s.len / 8], width, height)
        case .RGB:
            if s.len % 3 != 0 do return nil, .Encode_Size_Mismatch
            self.img^, ok = image.pixels_to_image((cast([^][3]byte)s.data)[:s.len / 3], width, height)
        case .RGB16:
            if s.len % 6 != 0 do return nil, .Encode_Size_Mismatch
            self.img^, ok = image.pixels_to_image((cast([^][3]u16)s.data)[:s.len / 6], width, height)
        case : trace.panic_log("unsupport option")
    }

   
    if !ok do return nil, .Encode_Size_Mismatch
    
    self.allocator = allocator
    

    out:bytes.Buffer
    err : image.Error = qoi.save_to_buffer(&out, self.img, allocator = allocator)
    if err != nil {
        ok = false
        return nil, err
    }
  
    return bytes.buffer_to_bytes(&out), nil
}

qoi_converter_encode_file :: proc (self:^qoi_converter, data:[]byte, in_fmt:color_fmt, width:int, height:int, save_file_path:string) -> Qoi_Error {
    out, err := qoi_converter_encode(self, data, in_fmt, width, height, context.temp_allocator)
    if err != nil do return err

    defer {
        delete(out, context.temp_allocator)
    }

    when is_android {
        //TODO (xfitgd)
        panic("")
    } else {
        file : ^os2.File
        file, err = os2.create(save_file_path)
        if err != nil do return err

        _, err = os2.write(file, out)
        if err != nil do return err

        err = os2.close(file)
        if err != nil do return err
    }

    return nil
}