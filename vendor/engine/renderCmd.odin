package engine

import "core:mem"
import "core:debug/trace"
import "core:sync"
import vk "vendor:vulkan"

import graphics_api "./graphics_api"

MAX_FRAMES_IN_FLIGHT :: 2
RenderCmd :: struct {}

__RenderCmd :: struct {
    scene: [dynamic]^IObject,
    sceneT: [dynamic]^IObject,
    refresh:[MAX_FRAMES_IN_FLIGHT]bool,
    cmds:[MAX_FRAMES_IN_FLIGHT][]graphics_api.CommandBuffer,
    objLock:sync.RW_Mutex
}

__gRenderCmd : [dynamic]^__RenderCmd
__gMainRenderCmdIdx : int = -1
__gRenderCmdMtx : sync.Mutex

RenderCmd_Init :: proc() -> ^RenderCmd {
    cmd := new(__RenderCmd)
    cmd.scene = mem.make_non_zeroed([dynamic]^IObject)
    cmd.sceneT = mem.make_non_zeroed([dynamic]^IObject)
    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        cmd.refresh[i] = false
        cmd.cmds[i] = mem.make_non_zeroed([]graphics_api.CommandBuffer, graphics_api.swapImgCnt)
        graphics_api.allocate_command_buffers(&cmd.cmds[i][0], graphics_api.swapImgCnt)
    }
    cmd.objLock = sync.RW_Mutex{}

    sync.mutex_lock(&__gRenderCmdMtx)
    non_zero_append(&__gRenderCmd, cmd)
    sync.mutex_unlock(&__gRenderCmdMtx)
    return (^RenderCmd)(cmd)
}

RenderCmd_Deinit :: proc(cmd: ^RenderCmd) {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)
    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        graphics_api.free_command_buffers(&cmd_.cmds[i][0], graphics_api.swapImgCnt)
        delete(cmd_.cmds[i])
    }
    delete(cmd_.scene)
    delete(cmd_.sceneT)

    sync.mutex_lock(&__gRenderCmdMtx)
    for cmd, i in __gRenderCmd {
        if cmd == cmd_ {
            ordered_remove(&__gRenderCmd, i)
            if i == __gMainRenderCmdIdx do __gMainRenderCmdIdx = -1
            break
        }
    }
    sync.mutex_unlock(&__gRenderCmdMtx)
    free(cmd)
}

RenderCmd_Show :: proc (_cmd: ^RenderCmd) -> bool {
    sync.mutex_lock(&__gRenderCmdMtx)
    defer sync.mutex_unlock(&__gRenderCmdMtx)
    for cmd, i in __gRenderCmd {
        if cmd == (^__RenderCmd)(_cmd) {
            RenderCmd_Refresh(_cmd)
            __gMainRenderCmdIdx = i
            return true
        }
    }
    return false
}

RenderCmd_AddObject :: proc(cmd: ^RenderCmd, obj: ^IObject) {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.objLock)
    defer sync.rw_mutex_shared_unlock(&cmd_.objLock)

    for objT,i in cmd_.scene {
        if objT == obj {
            ordered_remove(&cmd_.scene, i)
            break
        }
    }
    non_zero_append(&cmd_.scene, obj)
    RenderCmd_Refresh(cmd)
}

RenderCmd_AddObjects :: proc(cmd: ^RenderCmd, objs: ..^IObject) {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.objLock)
    defer sync.rw_mutex_shared_unlock(&cmd_.objLock)

    for objT,i in cmd_.scene {
        for obj in objs {
            if objT == obj {
                ordered_remove(&cmd_.scene, i)
                break
            }
        }
    }
    non_zero_append(&cmd_.scene, ..objs)
    if len(objs) > 0 do RenderCmd_Refresh(cmd)
}


RenderCmd_RemoveObject :: proc(cmd: ^RenderCmd, obj: ^IObject) {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.objLock)
    defer sync.rw_mutex_shared_unlock(&cmd_.objLock)

    for objT, i in cmd_.scene {
        if objT == obj {
            ordered_remove(&cmd_.scene, i)
            RenderCmd_Refresh(cmd)
            break
        }
    }
}

RenderCmd_RemoveAll :: proc(cmd: ^RenderCmd) {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.objLock)
    defer sync.rw_mutex_shared_unlock(&cmd_.objLock)
    objLen := len(cmd_.scene)
    clear(&cmd_.scene)
    if objLen > 0 do RenderCmd_Refresh(cmd)
}

RenderCmd_HasObject :: proc "contextless"(cmd: ^RenderCmd, obj: ^IObject) -> bool {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.objLock)
    defer sync.rw_mutex_shared_unlock(&cmd_.objLock)
    
    for objT in cmd_.scene {
        if objT == obj {
            return true
        }
    }
    return false
}

RenderCmd_GetObjectLen :: proc "contextless" (cmd: ^RenderCmd) -> int {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.objLock)
    defer sync.rw_mutex_shared_unlock(&cmd_.objLock)
    return len(cmd_.scene)
}

RenderCmd_GetObject :: proc "contextless" (cmd: ^RenderCmd, index: int) -> ^IObject {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.objLock)
    defer sync.rw_mutex_shared_unlock(&cmd_.objLock)
    return cmd_.scene[index]
}

RenderCmd_GetObjectIdx :: proc "contextless"(cmd: ^RenderCmd, obj: ^IObject) -> int {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)
    sync.rw_mutex_shared_lock(&cmd_.objLock)
    defer sync.rw_mutex_shared_unlock(&cmd_.objLock)
    for objT, i in cmd_.scene {
        if objT == obj {
            return i
        }
    }
    return -1
}

//! thread non safe
RenderCmd_GetObjects :: proc(cmd: ^RenderCmd) -> []^IObject {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)

    clear(&cmd_.sceneT)
    sync.rw_mutex_shared_lock(&cmd_.objLock)
    non_zero_append(&cmd_.sceneT, ..cmd_.scene[:])
    sync.rw_mutex_shared_unlock(&cmd_.objLock)
    return cmd_.sceneT[:]
}

RenderCmd_Refresh :: proc "contextless" (cmd: ^RenderCmd) {
    cmd_ :^__RenderCmd = (^__RenderCmd)(cmd)
    for &b in cmd_.refresh {
        b = true
    }
}

RenderCmd_RefreshAll :: proc "contextless" () {
    sync.mutex_lock(&__gRenderCmdMtx)
    defer sync.mutex_unlock(&__gRenderCmdMtx)
    for cmd in __gRenderCmd {
        for &b in cmd.refresh {
            b = true
        }
    }
}

__RenderCmd_Clean :: proc () {
    sync.mutex_lock(&__gRenderCmdMtx)
    defer sync.mutex_unlock(&__gRenderCmdMtx)
    delete(__gRenderCmd)
}

__RenderCmd_Create :: proc () {
    sync.mutex_lock(&__gRenderCmdMtx)
    defer sync.mutex_unlock(&__gRenderCmdMtx)
    __gRenderCmd = mem.make_non_zeroed([dynamic]^__RenderCmd)
}