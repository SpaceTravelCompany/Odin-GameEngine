package engine

import "core:image"


// ============================================================================
// Image Converter Interface
// ============================================================================

/*
Gets the width of the loaded image

Polymorphic procedure that works with different converter types
*/
image_converter_width :: proc {
    webp_converter_width,
    png_converter_width,
    qoi_converter_width,
}

/*
Gets the height of the loaded image

Polymorphic procedure that works with different converter types
*/
image_converter_height :: proc {
    webp_converter_height,
    png_converter_height,
    qoi_converter_height,
}

/*
Gets the size in bytes of the loaded image

Polymorphic procedure that works with different converter types
*/
image_converter_size :: proc {
    webp_converter_size,
    png_converter_size,
    qoi_converter_size,
}

/*
Gets the number of frames in the image

Polymorphic procedure that works with different converter types
Only WebP converter supports multiple frames
*/
image_converter_frame_cnt :: proc {
    webp_converter_frame_cnt,
}

/*
Deinitializes and cleans up image converter resources

Polymorphic procedure that works with different converter types

Inputs:
- self: Pointer to the converter to deinitialize

*/
image_converter_deinit :: proc (self:^$T) where T == webp_converter || T == qoi_converter || T == png_converter {
    when T == webp_converter {
        webp_converter_deinit(self)
    } else {
        if self.img != nil {
            if self.img.pixels.buf != nil {
                image.destroy(self.img, self.allocator)
            } else {
                free(self.img, self.allocator)
            }
            self.img = nil
        }
    }
}

/*
Loads an image from byte data

Polymorphic procedure that works with different converter types

Inputs:
- self: Pointer to the converter
- data: The image data as bytes
- out_fmt: The desired output color format
- allocator: The allocator to use

Returns:
- The decoded image data as bytes
- An error if loading failed
*/
image_converter_load :: proc {
    webp_converter_load,
    png_converter_load,
    qoi_converter_load,
}

/*
Loads an image from a file

Polymorphic procedure that works with different converter types

Inputs:
- self: Pointer to the converter
- file_path: Path to the image file
- out_fmt: The desired output color format
- allocator: The allocator to use

Returns:
- The decoded image data as bytes
- An error if loading failed
*/
image_converter_load_file :: proc {
    webp_converter_load_file,
    png_converter_load_file,
    qoi_converter_load_file,
}

/*
Encodes image data to a format

Polymorphic procedure that works with different converter types
Currently only QOI converter supports encoding
*/
image_converter_encode :: proc {
    qoi_converter_encode,
}

/*
Encodes image data and saves it to a file

Polymorphic procedure that works with different converter types
Currently only QOI converter supports encoding
*/
image_converter_encode_file :: proc {
    qoi_converter_encode_file,
}