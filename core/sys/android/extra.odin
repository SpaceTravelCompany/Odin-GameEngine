#+build linux
package android

import "core:strings"
import "core:mem"

AssetFileError :: enum {
	None,
	Err,
}

asset_read_file :: proc(path:string, allocator := context.allocator) -> (data:[]u8, err:AssetFileError = .None) {
    pathT := strings.clone_to_cstring(path, context.temp_allocator)
    defer delete(pathT, context.temp_allocator)
    
    asset := AAssetManager_open(get_android_app().activity.assetManager, pathT, .BUFFER)
    __size := AAsset_getLength64(asset)

    data = mem.make_non_zeroed_slice([]u8, auto_cast __size, allocator)

    __read : type_of(__size) = 0
    for __read < __size {
        i := AAsset_read(asset, auto_cast &data[__read], auto_cast(__size - __read))
        if i < 0 {
            delete(data)
            err = .Err
            break
        } else if i == 0 {
            break
        }
        __read += auto_cast i
    }
    AAsset_close(asset)
    return
}