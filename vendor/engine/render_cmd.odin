package engine

import "core:mem"
import "core:debug/trace"
import "core:sync"
import vk "vendor:vulkan"

import sys "./sys"

MAX_FRAMES_IN_FLIGHT :: 2
render_cmd :: struct {}

__render_cmd :: struct {
    scene: [dynamic]^iobject,
    scene_t: [dynamic]^iobject,
    refresh:[MAX_FRAMES_IN_FLIGHT]bool,
    cmds:[MAX_FRAMES_IN_FLIGHT][]sys.command_buffer,
    obj_lock:sync.RW_Mutex
}

__g_render_cmd : [dynamic]^__render_cmd
__g_main_render_cmd_idx : int = -1
__g_render_cmd_mtx : sync.Mutex

render_cmd_init :: proc() -> ^render_cmd {
    cmd := new(__render_cmd)
    cmd.scene = mem.make_non_zeroed([dynamic]^iobject)
    cmd.scene_t = mem.make_non_zeroed([dynamic]^iobject)
    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        cmd.refresh[i] = false
        cmd.cmds[i] = mem.make_non_zeroed([]sys.command_buffer, sys.swap_img_cnt)
        sys.allocate_command_buffers(&cmd.cmds[i][0], sys.swap_img_cnt)
    }
    cmd.obj_lock = sync.RW_Mutex{}

    sync.mutex_lock(&__g_render_cmd_mtx)
    non_zero_append(&__g_render_cmd, cmd)
    sync.mutex_unlock(&__g_render_cmd_mtx)
    return (^render_cmd)(cmd)
}

render_cmd_deinit :: proc(cmd: ^render_cmd) {
    cmd_ :^__render_cmd = (^__render_cmd)(cmd)
    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        sys.free_command_buffers(&cmd_.cmds[i][0], sys.swap_img_cnt)
        delete(cmd_.cmds[i])
    }
    delete(cmd_.scene)
    delete(cmd_.scene_t)

    sync.mutex_lock(&__g_render_cmd_mtx)
    for cmd, i in __g_render_cmd {
        if cmd == cmd_ {
            ordered_remove(&__g_render_cmd, i)
            if i == __g_main_render_cmd_idx do __g_main_render_cmd_idx = -1
            break
        }
    }
    sync.mutex_unlock(&__g_render_cmd_mtx)
    free(cmd)
}

render_cmd_show :: proc (_cmd: ^render_cmd) -> bool {
    sync.mutex_lock(&__g_render_cmd_mtx)
    defer sync.mutex_unlock(&__g_render_cmd_mtx)
    for cmd, i in __g_render_cmd {
        if cmd == (^__render_cmd)(_cmd) {
            render_cmd_refresh(_cmd)
            __g_main_render_cmd_idx = i
            return true
        }
    }
    return false
}

render_cmd_add_object :: proc(cmd: ^render_cmd, obj: ^iobject) {
    cmd_ :^__render_cmd = (^__render_cmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.obj_lock)
    defer sync.rw_mutex_shared_unlock(&cmd_.obj_lock)

    for obj_t,i in cmd_.scene {
        if obj_t == obj {
            ordered_remove(&cmd_.scene, i)
            break
        }
    }
    non_zero_append(&cmd_.scene, obj)
    render_cmd_refresh(cmd)
}

render_cmd_add_objects :: proc(cmd: ^render_cmd, objs: ..^iobject) {
    cmd_ :^__render_cmd = (^__render_cmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.obj_lock)
    defer sync.rw_mutex_shared_unlock(&cmd_.obj_lock)

    for obj_t,i in cmd_.scene {
        for obj in objs {
            if obj_t == obj {
                ordered_remove(&cmd_.scene, i)
                break
            }
        }
    }
    non_zero_append(&cmd_.scene, ..objs)
    if len(objs) > 0 do render_cmd_refresh(cmd)
}


render_cmd_remove_object :: proc(cmd: ^render_cmd, obj: ^iobject) {
    cmd_ :^__render_cmd = (^__render_cmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.obj_lock)
    defer sync.rw_mutex_shared_unlock(&cmd_.obj_lock)

    for obj_t, i in cmd_.scene {
        if obj_t == obj {
            ordered_remove(&cmd_.scene, i)
            render_cmd_refresh(cmd)
            break
        }
    }
}

render_cmd_remove_all :: proc(cmd: ^render_cmd) {
    cmd_ :^__render_cmd = (^__render_cmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.obj_lock)
    defer sync.rw_mutex_shared_unlock(&cmd_.obj_lock)
    obj_len := len(cmd_.scene)
    clear(&cmd_.scene)
    if obj_len > 0 do render_cmd_refresh(cmd)
}

render_cmd_has_object :: proc "contextless"(cmd: ^render_cmd, obj: ^iobject) -> bool {
    cmd_ :^__render_cmd = (^__render_cmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.obj_lock)
    defer sync.rw_mutex_shared_unlock(&cmd_.obj_lock)
    
    for obj_t in cmd_.scene {
        if obj_t == obj {
            return true
        }
    }
    return false
}

render_cmd_get_object_len :: proc "contextless" (cmd: ^render_cmd) -> int {
    cmd_ :^__render_cmd = (^__render_cmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.obj_lock)
    defer sync.rw_mutex_shared_unlock(&cmd_.obj_lock)
    return len(cmd_.scene)
}

render_cmd_get_object :: proc "contextless" (cmd: ^render_cmd, index: int) -> ^iobject {
    cmd_ :^__render_cmd = (^__render_cmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.obj_lock)
    defer sync.rw_mutex_shared_unlock(&cmd_.obj_lock)
    return cmd_.scene[index]
}

render_cmd_get_object_idx :: proc "contextless"(cmd: ^render_cmd, obj: ^iobject) -> int {
    cmd_ :^__render_cmd = (^__render_cmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.obj_lock)
    defer sync.rw_mutex_shared_unlock(&cmd_.obj_lock)
    for obj_t, i in cmd_.scene {
        if obj_t == obj {
            return i
        }
    }
    return -1
}

//! thread non safe
render_cmd_get_objects :: proc(cmd: ^render_cmd) -> []^iobject {
    cmd_ :^__render_cmd = (^__render_cmd)(cmd)

    clear(&cmd_.scene_t)
    sync.rw_mutex_shared_lock(&cmd_.obj_lock)
    non_zero_append(&cmd_.scene_t, ..cmd_.scene[:])
    sync.rw_mutex_shared_unlock(&cmd_.obj_lock)
    return cmd_.scene_t[:]
}

render_cmd_refresh :: proc "contextless" (cmd: ^render_cmd) {
    cmd_ :^__render_cmd = (^__render_cmd)(cmd)
    for &b in cmd_.refresh {
        b = true
    }
}

render_cmd_refresh_all :: proc "contextless" () {
    sync.mutex_lock(&__g_render_cmd_mtx)
    defer sync.mutex_unlock(&__g_render_cmd_mtx)
    for cmd in __g_render_cmd {
        for &b in cmd.refresh {
            b = true
        }
    }
}

__render_cmd_clean :: proc () {
    sync.mutex_lock(&__g_render_cmd_mtx)
    defer sync.mutex_unlock(&__g_render_cmd_mtx)
    delete(__g_render_cmd)
}

__render_cmd_create :: proc () {
    sync.mutex_lock(&__g_render_cmd_mtx)
    defer sync.mutex_unlock(&__g_render_cmd_mtx)
    __g_render_cmd = mem.make_non_zeroed([dynamic]^__render_cmd)
}