package engine

import "core:mem"
import "core:debug/trace"
import "core:sync"
import vk "vendor:vulkan"
import "base:runtime"


/*
Render command structure for managing render objects

Manages a collection of objects to be rendered and their command buffers
*/
render_cmd :: struct {
	scene: ^[dynamic]^iobject,
    refresh:[MAX_FRAMES_IN_FLIGHT]bool,
    cmds:[MAX_FRAMES_IN_FLIGHT][]command_buffer,
    obj_lock:sync.Mutex,
	check_init:mem.ICheckInit,
	creation_allocator: runtime.Allocator,
}

@private __g_render_cmd : [dynamic]^render_cmd = nil
@private __g_main_render_cmd_idx : int = -1
@private __g_render_cmd_mtx : sync.Mutex

@private __g_viewports: [dynamic]^viewport = nil

@private __g_default_viewport: viewport
@private __g_default_camera: camera
@private __g_default_projection: projection

/*
Initializes a new render command structure

Make render_cmd.scene manually.

Returns:
- Pointer to the initialized render command
- Allocator error if allocation failed
*/
render_cmd_init :: proc(_scene: ^[dynamic]^iobject, allocator := context.allocator) -> (cmd: ^render_cmd, err: mem.Allocator_Error) #optional_allocator_error {
    cmd = new(render_cmd, allocator) or_return
    
    allocated_count := 0
    defer if err != nil {
        for j in 0..<allocated_count {
            delete(cmd.cmds[j], allocator)
        }
        free(cmd, allocator)
        cmd = nil
    }

    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        cmd.refresh[i] = false
        cmd.cmds[i] = mem.make_non_zeroed([]command_buffer, swap_img_cnt) or_return
        allocated_count += 1
        allocate_command_buffers(&cmd.cmds[i][0], swap_img_cnt)
    }
    cmd.obj_lock = sync.Mutex{}

    sync.mutex_lock(&__g_render_cmd_mtx)
    non_zero_append(&__g_render_cmd, cmd)
    sync.mutex_unlock(&__g_render_cmd_mtx)

	cmd.scene = _scene

	mem.ICheckInit_Init(&cmd.check_init)
	cmd.creation_allocator = allocator
    return
}

/*
Deinitializes and cleans up render command resources

Inputs:
- cmd: Pointer to the render command to deinitialize

Returns:
- None
*/
render_cmd_deinit :: proc(cmd: ^render_cmd) {
	mem.ICheckInit_Deinit(&cmd.check_init)

    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        free_command_buffers(&cmd.cmds[i][0], swap_img_cnt)
        delete(cmd.cmds[i])
    }

    sync.mutex_lock(&__g_render_cmd_mtx)
    for cmd, i in __g_render_cmd {
        if cmd == cmd {
            ordered_remove(&__g_render_cmd, i)
            if i == __g_main_render_cmd_idx do __g_main_render_cmd_idx = -1
            break
        }
    }
    sync.mutex_unlock(&__g_render_cmd_mtx)
    free(cmd, cmd.creation_allocator)
}

/*
Sets the render command as the main one to display

Inputs:
- _cmd: Pointer to the render command to show

Returns:
- `true` if successful, `false` if the command was not found
*/
render_cmd_show :: proc "contextless" (_cmd: ^render_cmd) -> bool {
	mem.ICheckInit_Check(&_cmd.check_init)
	
    sync.mutex_lock(&__g_render_cmd_mtx)
    defer sync.mutex_unlock(&__g_render_cmd_mtx)
    for cmd, i in __g_render_cmd {
        if cmd == _cmd {
            render_cmd_refresh(_cmd)
            __g_main_render_cmd_idx = i
            return true
        }
    }
    return false
}


/*
Changes the scene of the render command
*/
render_cmd_change_scene :: proc "contextless" (cmd: ^render_cmd, _scene: ^[dynamic]^iobject) {
	sync.mutex_lock(&cmd.obj_lock)
	defer sync.mutex_unlock(&cmd.obj_lock)
	
	if cmd.scene != _scene {
		cmd.scene = _scene
		render_cmd_refresh(cmd)
	}
}

/*
Adds an object to the render command's scene

Inputs:
- cmd: Pointer to the render command
- obj: Pointer to the object to add

Returns:
- None
*/
render_cmd_add_object :: proc(cmd: ^render_cmd, obj: ^iobject) {
	mem.ICheckInit_Check(&cmd.check_init)
	
    sync.mutex_lock(&cmd.obj_lock)
    defer sync.mutex_unlock(&cmd.obj_lock)

    for obj_t,i in cmd.scene^ {
        if obj_t == obj {
            ordered_remove(cmd.scene, i)
            break
        }
    }
    non_zero_append(cmd.scene, obj)
    render_cmd_refresh(cmd)
}

/*
Adds multiple objects to the render command's scene

Inputs:
- cmd: Pointer to the render command
- objs: Variable number of object pointers to add

Returns:
- None
*/
render_cmd_add_objects :: proc(cmd: ^render_cmd, objs: ..^iobject) {
	mem.ICheckInit_Check(&cmd.check_init)
	
    sync.mutex_lock(&cmd.obj_lock)
    defer sync.mutex_unlock(&cmd.obj_lock)

    for obj_t,i in cmd.scene^ {
        for obj in objs {
            if obj_t == obj {
                ordered_remove(cmd.scene, i)
                break
            }
        }
    }
    non_zero_append(cmd.scene, ..objs)
    if len(objs) > 0 do render_cmd_refresh(cmd)
}


/*
Removes an object from the render command's scene

Inputs:
- cmd: Pointer to the render command
- obj: Pointer to the object to remove

Returns:
- None
*/
render_cmd_remove_object :: proc(cmd: ^render_cmd, obj: ^iobject) {
	mem.ICheckInit_Check(&cmd.check_init)
	
    sync.mutex_lock(&cmd.obj_lock)
    defer sync.mutex_unlock(&cmd.obj_lock)

    for obj_t, i in cmd.scene^ {
        if obj_t == obj {
            ordered_remove(cmd.scene, i)
            render_cmd_refresh(cmd)
            break
        }
    }
}

/*
Removes all objects from the render command's scene

Inputs:
- cmd: Pointer to the render command

Returns:
- None
*/
render_cmd_remove_all :: proc(cmd: ^render_cmd) {
	mem.ICheckInit_Check(&cmd.check_init)
	
    sync.mutex_lock(&cmd.obj_lock)
    defer sync.mutex_unlock(&cmd.obj_lock)
    obj_len := len(cmd.scene)
    clear(cmd.scene)
    if obj_len > 0 do render_cmd_refresh(cmd)
}

/*
Checks if an object is in the render command's scene

Inputs:
- cmd: Pointer to the render command
- obj: Pointer to the object to check

Returns:
- `true` if the object is in the scene, `false` otherwise
*/
render_cmd_has_object :: proc "contextless"(cmd: ^render_cmd, obj: ^iobject) -> bool {
	mem.ICheckInit_Check(&cmd.check_init)
	
    sync.mutex_lock(&cmd.obj_lock)
    defer sync.mutex_unlock(&cmd.obj_lock)
    
    for obj_t in cmd.scene^ {
        if obj_t == obj {
            return true
        }
    }
    return false
}

/*
Gets the number of objects in the render command's scene

Inputs:
- cmd: Pointer to the render command

Returns:
- The number of objects in the scene
*/
render_cmd_get_object_len :: proc "contextless" (cmd: ^render_cmd) -> int {
	mem.ICheckInit_Check(&cmd.check_init)
	
    sync.mutex_lock(&cmd.obj_lock)
    defer sync.mutex_unlock(&cmd.obj_lock)
    return len(cmd.scene)
}

/*
Gets an object from the render command's scene by index

Inputs:
- cmd: Pointer to the render command
- index: The index of the object to get

Returns:
- Pointer to the object at the specified index
*/
render_cmd_get_object :: proc "contextless" (cmd: ^render_cmd, index: int) -> ^iobject {
	mem.ICheckInit_Check(&cmd.check_init)
	
    sync.mutex_lock(&cmd.obj_lock)
    defer sync.mutex_unlock(&cmd.obj_lock)
    return cmd.scene^[index]
}

/*
Gets the index of an object in the render command's scene

Inputs:
- cmd: Pointer to the render command
- obj: Pointer to the object to find

Returns:
- The index of the object, or -1 if not found
*/
render_cmd_get_object_idx :: proc "contextless"(cmd: ^render_cmd, obj: ^iobject) -> int {
    for obj_t, i in cmd.scene^ {
        if obj_t == obj {
            return i
        }
    }
    return -1
}

/*
Gets all objects from the render command's scene

**Note:** This function is not thread-safe

Inputs:
- cmd: Pointer to the render command

Returns:
- A slice of all objects in the scene
*/
render_cmd_get_objects :: proc(cmd: ^render_cmd) -> []^iobject {
    return cmd.scene^[:]
}

/*
Marks the render command for refresh on all frames in flight

Inputs:
- cmd: Pointer to the render command

Returns:
- None
*/
render_cmd_refresh :: proc "contextless" (cmd: ^render_cmd) {
    for &b in cmd.refresh {
        b = true
    }
}

/*
Marks all render commands for refresh on all frames in flight

Returns:
- None
*/
render_cmd_refresh_all :: proc "contextless" () {
    sync.mutex_lock(&__g_render_cmd_mtx)
    defer sync.mutex_unlock(&__g_render_cmd_mtx)
    for cmd in __g_render_cmd {
        for &b in cmd.refresh {
            b = true
        }
    }
}

@(private) __render_cmd_clean :: proc () {
	delete(__g_render_cmd)
	delete(__g_viewports)

	camera_deinit(&__g_default_camera)
	projection_deinit(&__g_default_projection)
}

@(private) __render_cmd_create :: proc() {
	__g_render_cmd = mem.make_non_zeroed([dynamic]^render_cmd)
	__g_viewports = mem.make_non_zeroed([dynamic]^viewport)

	camera_init(&__g_default_camera)
	projection_init_matrix_ortho_window(&__g_default_projection, auto_cast window_width(), auto_cast window_height())
	
	__g_default_viewport = viewport{
		camera = &__g_default_camera,
		projection = &__g_default_projection,
	}
	viewport_init_update(&__g_default_viewport)

	non_zero_append(&__g_viewports, &__g_default_viewport)
}

/*
size update all render commands' projection (only ortho windowprojection)

Inputs:
- None

Returns:
- None
*/
render_cmd_size_all :: proc () {
	sync.mutex_lock(&__g_render_cmd_mtx)
	defer sync.mutex_unlock(&__g_render_cmd_mtx)
	for cmd in __g_viewports {
		projection_size(cmd.projection)
	}
}