package engine

import "core:image"


// ============================================================================
// Image Converter Interface
// ============================================================================

image_converter_width :: proc {
    webp_converter_width,
    png_converter_width,
    qoi_converter_width,
}

image_converter_height :: proc {
    webp_converter_height,
    png_converter_height,
    qoi_converter_height,
}

image_converter_size :: proc {
    webp_converter_size,
    png_converter_size,
    qoi_converter_size,
}

image_converter_frame_cnt :: proc {
    webp_converter_frame_cnt,
}

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

image_converter_load :: proc {
    webp_converter_load,
    png_converter_load,
    qoi_converter_load,
}

image_converter_load_file :: proc {
    webp_converter_load_file,
    png_converter_load_file,
    qoi_converter_load_file,
}

image_converter_encode :: proc {
    qoi_converter_encode,
}

image_converter_encode_file :: proc {
    qoi_converter_encode_file,
}