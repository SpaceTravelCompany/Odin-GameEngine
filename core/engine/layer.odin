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
layer :: struct {
	visible: bool,
	scene: ^[dynamic]^iobject,
    cmd:command_buffer,
    obj_lock:sync.Mutex,
	check_init:mem.ICheckInit,
	creation_allocator: runtime.Allocator,
	cmd_pool: vk.CommandPool,
}

@private __g_layer : [dynamic]^layer = nil
@private __g_layer_mtx : sync.Mutex

@private __g_viewports: [dynamic]^viewport = nil

@private __g_default_viewport: viewport
@private __g_default_camera: camera
@private __g_default_projection: projection

/*
Initializes a new render command structure

Make layer.scene manually.
**_scene can be nil**

Returns:
- Pointer to the initialized render command
- Allocator error if allocation failed
*/
layer_init :: proc(_scene: ^[dynamic]^iobject, allocator := context.allocator) -> (cmd: ^layer, err: mem.Allocator_Error) #optional_allocator_error {
    cmd = new(layer, allocator) or_return

	res := vk.CreateCommandPool(vk_device, &vk.CommandPoolCreateInfo{
		sType = vk.StructureType.COMMAND_POOL_CREATE_INFO,
		flags = {vk.CommandPoolCreateFlag.RESET_COMMAND_BUFFER},
		queueFamilyIndex = vk_graphics_family_index,
	}, nil, &cmd.cmd_pool)
	if res != .SUCCESS do trace.panic_log("vk.CreateCommandPool(&vk_cmd_pool) : ", res)

    allocate_command_buffers(&cmd.cmd, 1, cmd.cmd_pool)

    cmd.obj_lock = sync.Mutex{}

    sync.mutex_lock(&__g_layer_mtx)
    non_zero_append(&__g_layer, cmd)
    sync.mutex_unlock(&__g_layer_mtx)

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
layer_deinit :: proc(cmd: ^layer) {
	mem.ICheckInit_Deinit(&cmd.check_init)

    free_command_buffers(&cmd.cmd, 1, cmd.cmd_pool)

    sync.mutex_lock(&__g_layer_mtx)
    for cmd, i in __g_layer {
        if cmd == cmd {
            ordered_remove(&__g_layer, i)
            break
        }
    }
    sync.mutex_unlock(&__g_layer_mtx)
	vk.DestroyCommandPool(vk_device, cmd.cmd_pool, nil)
    free(cmd, cmd.creation_allocator)
}

/*
Sets the render command as visible

Inputs:
- _cmd: Pointer to the render command to set visible

Returns:
- `true` if successful, `false` if the command was not found
*/
layer_show :: proc "contextless" (_cmd: ^layer) {
	mem.ICheckInit_Check(&_cmd.check_init)
	
    sync.mutex_lock(&__g_layer_mtx)
    for cmd in __g_layer {
        if cmd == _cmd {
            cmd.visible = true
			sync.mutex_unlock(&__g_layer_mtx)
            return
        }
    }
    trace.panic_log("layer_show: layer not found")
}

/*
Sets the render command as hidden

Inputs:
- _cmd: Pointer to the render command to hide

Returns:
- `true` if successful, `false` if the command was not found
*/
layer_hide :: proc "contextless" (_cmd: ^layer) -> bool {
	mem.ICheckInit_Check(&_cmd.check_init)
	
    sync.mutex_lock(&__g_layer_mtx)
    defer sync.mutex_unlock(&__g_layer_mtx)
    for cmd in __g_layer {
        if cmd == _cmd {
            cmd.visible = false
            return true
        }
    }
    return false
}


/*
Changes the scene of the render command
*/
layer_change_scene :: proc "contextless" (cmd: ^layer, _scene: ^[dynamic]^iobject) {
	sync.mutex_lock(&cmd.obj_lock)
	defer sync.mutex_unlock(&cmd.obj_lock)
	
	if cmd.scene != _scene {
		cmd.scene = _scene
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
layer_add_object :: proc(cmd: ^layer, obj: ^iobject) {
	mem.ICheckInit_Check(&cmd.check_init)
	if cmd.scene == nil {
		trace.panic_log("layer_add_object: cmd.scene is nil")
	}

    sync.mutex_lock(&cmd.obj_lock)
    defer sync.mutex_unlock(&cmd.obj_lock)

    // for obj_t,i in cmd.scene^ {
    //     if obj_t == obj {
    //         ordered_remove(cmd.scene, i)
    //         break
    //     }
    // }
    non_zero_append(cmd.scene, obj)
}

/*
Adds multiple objects to the render command's scene

Inputs:
- cmd: Pointer to the render command
- objs: Variable number of object pointers to add

Returns:
- None
*/
layer_add_objects :: proc(cmd: ^layer, objs: ..^iobject) {
	mem.ICheckInit_Check(&cmd.check_init)
	if cmd.scene == nil {
		trace.panic_log("layer_add_object: cmd.scene is nil")
	}
	
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
}


/*
Removes an object from the render command's scene

Inputs:
- cmd: Pointer to the render command
- obj: Pointer to the object to remove

Returns:
- None
*/
layer_remove_object :: proc(cmd: ^layer, obj: ^iobject) {
	mem.ICheckInit_Check(&cmd.check_init)
	if cmd.scene == nil {
		trace.panic_log("layer_add_object: cmd.scene is nil")
	}
	
    sync.mutex_lock(&cmd.obj_lock)
    defer sync.mutex_unlock(&cmd.obj_lock)

    for obj_t, i in cmd.scene^ {
        if obj_t == obj {
            ordered_remove(cmd.scene, i)
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
layer_remove_all :: proc(cmd: ^layer) {
	mem.ICheckInit_Check(&cmd.check_init)
	if cmd.scene == nil {
		trace.panic_log("layer_add_object: cmd.scene is nil")
	}
	
    sync.mutex_lock(&cmd.obj_lock)
    defer sync.mutex_unlock(&cmd.obj_lock)
    obj_len := len(cmd.scene)
    clear(cmd.scene)
}

/*
Checks if an object is in the render command's scene

Inputs:
- cmd: Pointer to the render command
- obj: Pointer to the object to check

Returns:
- `true` if the object is in the scene, `false` otherwise
*/
layer_has_object :: proc "contextless"(cmd: ^layer, obj: ^iobject) -> bool {
	mem.ICheckInit_Check(&cmd.check_init)
	if cmd.scene == nil {
		trace.panic_log("layer_add_object: cmd.scene is nil")
	}
	
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
layer_get_object_len :: proc "contextless" (cmd: ^layer) -> int {
	mem.ICheckInit_Check(&cmd.check_init)
	if cmd.scene == nil {
		trace.panic_log("layer_add_object: cmd.scene is nil")
	}
	
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
layer_get_object :: proc "contextless" (cmd: ^layer, index: int) -> ^iobject {
	mem.ICheckInit_Check(&cmd.check_init)
	if cmd.scene == nil {
		trace.panic_log("layer_add_object: cmd.scene is nil")
	}
	
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
layer_get_object_idx :: proc "contextless"(cmd: ^layer, obj: ^iobject) -> int {
	if cmd.scene == nil {
		trace.panic_log("layer_add_object: cmd.scene is nil")
	}
    for obj_t, i in cmd.scene^ {
        if obj_t == obj {
            return i
        }
    }
    return -1
}


@(private) __layer_clean :: proc () {
	delete(__g_layer)
	delete(__g_viewports)

	camera_deinit(&__g_default_camera)
	projection_deinit(&__g_default_projection)
}

@(private) __layer_create :: proc() {
	__g_layer = mem.make_non_zeroed([dynamic]^layer)
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
layer_size_all :: proc () {
	sync.mutex_lock(&__g_layer_mtx)
	defer sync.mutex_unlock(&__g_layer_mtx)
	for cmd in __g_viewports {
		projection_size(cmd.projection)
	}
}