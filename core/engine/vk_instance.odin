#+private
package engine

import "base:library"
import "base:runtime"
import "core:dynlib"
import "core:fmt"
import "core:mem"
import "core:strings"
import vk "vendor:vulkan"
import "vendor:glfw"
import "core:log"


// ============================================================================
// Debug Callback
// ============================================================================

vk_debug_callback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	context = default_context

	//#VUID-VkSwapchainCreateInfoKHR-pNext-07781 1284057537
	//#VUID-vkDestroySemaphore-semaphore-05149 -1813885519
	switch pCallbackData.messageIdNumber {
	case 1284057537, -1813885519:
		return false
	}
	log.infof("%s\n", pCallbackData.pMessage)

	return false
}


// ============================================================================
// Instance Creation
// ============================================================================

load_and_check_vulkan_support :: proc() -> bool {
	when is_web {
		return false
	}

	ok: bool
	when ODIN_OS == .Windows {
		vk_library, ok = dynlib.load_library("vulkan-1.dll")
		if !ok do return false
	} else {
		vk_library, ok = dynlib.load_library("libvulkan.so.1")
		if !ok {
			vk_library, ok = dynlib.load_library("libvulkan.so")
			if !ok do return false
		}
	}
	rawFunc: rawptr
	rawFunc, ok = dynlib.symbol_address(vk_library, "vkGetInstanceProcAddr")
	if !ok do log.panicf("rawFunc, ok = dynlib.symbol_address(vk_library, \"vkGetInstanceProcAddr\")\n")
	vk_get_instance_proc_addr = auto_cast rawFunc
	vk.load_proc_addresses_global(rawFunc)

	return vk.CreateInstance != nil
}

vk_create_instance :: proc() {
	appInfo := vk.ApplicationInfo {
		apiVersion         = vk.API_VERSION_1_4,
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = "Xfit",
		pApplicationName   = ODIN_BUILD_PROJECT_NAME,
	}
	FN_vkEnumerateInstanceVersion := vk.ProcEnumerateInstanceVersion(vk.GetInstanceProcAddr(nil, "vkEnumerateInstanceVersion"))
	if FN_vkEnumerateInstanceVersion == nil {
		log.infof("SYSLOG : vulkan 1.0 device, set api version 1.0\n")
		appInfo.apiVersion = vk.API_VERSION_1_0
		vulkan_version = {1,0,0}
	} else {
		vk_ver:u32
		FN_vkEnumerateInstanceVersion(&vk_ver)
		vulkan_version = { vk.VK_VERSION_MAJOR(vk_ver), vk.VK_VERSION_MINOR(vk_ver), vk.VK_VERSION_PATCH(vk_ver) }
		log.infof("SYSLOG : vulkan version : %d.%d.%d\n", vulkan_version.major, vulkan_version.minor, vulkan_version.patch)
	}
	glfwLen := 0
	glfwExtensions : []cstring
	when !library.is_mobile {
		glfwExtensions = glfw.GetRequiredInstanceExtensions()
		glfwLen = len(glfwExtensions)
	}
	instanceExtNames :[dynamic]cstring = mem.make_non_zeroed([dynamic]cstring,  context.temp_allocator)
	defer delete(instanceExtNames)
	layerNames := mem.make_non_zeroed([dynamic]cstring, 0, len(LAYERS), context.temp_allocator)
	defer delete(layerNames)

	non_zero_append(&instanceExtNames, vk.KHR_SURFACE_EXTENSION_NAME)

	layerPropCnt: u32
	vk.EnumerateInstanceLayerProperties(&layerPropCnt, nil)

	if layerPropCnt > 0 {
		availableLayers := mem.make_non_zeroed([]vk.LayerProperties, layerPropCnt, context.temp_allocator)
		defer delete(availableLayers, context.temp_allocator)

		vk.EnumerateInstanceLayerProperties(&layerPropCnt, &availableLayers[0])

		for &l in availableLayers {
			for _, i in LAYERS {
				if !LAYERS_CHECK[i] && mem.compare((transmute([^]byte)LAYERS[i])[:len(LAYERS[i])], l.layerName[:len(LAYERS[i])]) == 0 {
					when !ODIN_DEBUG {
						if LAYERS[i] == "VK_LAYER_KHRONOS_validation" do continue
					}
					non_zero_append(&layerNames, LAYERS[i])
					LAYERS_CHECK[i] = true
					log.infof("SYSLOG : vulkan %s instance layer support\n", LAYERS[i])
				}
			}
		}
	}

	instanceExtCnt: u32
	vk.EnumerateInstanceExtensionProperties(nil, &instanceExtCnt, nil)

	availableInstanceExts := mem.make_non_zeroed([]vk.ExtensionProperties, instanceExtCnt, context.temp_allocator)
	defer delete(availableInstanceExts, context.temp_allocator)

	vk.EnumerateInstanceExtensionProperties(nil, &instanceExtCnt, &availableInstanceExts[0])

	for &e in availableInstanceExts {
		for _, i in INSTANCE_EXTENSIONS {
			if !INSTANCE_EXTENSIONS_CHECK[i] &&
			   mem.compare((transmute([^]byte)INSTANCE_EXTENSIONS[i])[:len(INSTANCE_EXTENSIONS[i])], e.extensionName[:len(INSTANCE_EXTENSIONS[i])]) == 0 {
				non_zero_append(&instanceExtNames, INSTANCE_EXTENSIONS[i])
				INSTANCE_EXTENSIONS_CHECK[i] = true
				log.infof("SYSLOG : vulkan %s instance ext support\n", INSTANCE_EXTENSIONS[i])
			}
		}
	}
	if validation_layer_support() {
		non_zero_append(&instanceExtNames, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)

		log.infof("SYSLOG : vulkan validation layer enable\n")
	} else {
		log.infof("SYSLOG : vulkan validation layer disable\n")
	}

	when library.is_android {
		non_zero_append(&instanceExtNames, "VK_KHR_android_surface")
	} else {
	}

	when !library.is_mobile {
		insLen := len(instanceExtNames)
		con: for &glfw in glfwExtensions {
			for &ext in instanceExtNames[:insLen] {
				if strings.compare(string(glfw), string(ext)) == 0 do continue con
			}
			non_zero_append(&instanceExtNames, glfw)
		}
	}

	instanceCreateInfo := vk.InstanceCreateInfo {
		sType                   = vk.StructureType.INSTANCE_CREATE_INFO,
		pApplicationInfo        = &appInfo,
		enabledLayerCount       = auto_cast len(layerNames),
		ppEnabledLayerNames     = &layerNames[0] if len(layerNames) > 0 else nil,
		enabledExtensionCount   = auto_cast len(instanceExtNames),
		ppEnabledExtensionNames = &instanceExtNames[0],
		pNext                   = nil,
		flags                   = vk.InstanceCreateFlags{.ENUMERATE_PORTABILITY_KHR} if vk_khr_portability_enumeration_support() else vk.InstanceCreateFlags{},
	}

	res := vk.CreateInstance(&instanceCreateInfo, nil, &vk_instance)
	if res != vk.Result.SUCCESS do log.panicf("vk.CreateInstance(&instanceCreateInfo, nil, &vk_instance) : %s\n", res)

	vk.load_proc_addresses_instance(vk_instance)

	if validation_layer_support() && ODIN_DEBUG {
		debugUtilsCreateInfo := vk.DebugUtilsMessengerCreateInfoEXT {
			sType = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = vk.DebugUtilsMessageSeverityFlagsEXT{.ERROR, .VERBOSE, .WARNING, .INFO},
			messageType     = vk.DebugUtilsMessageTypeFlagsEXT {.GENERAL, .VALIDATION, .PERFORMANCE},
			pfnUserCallback = vk_debug_callback,
			pUserData       = nil,
		}
		vk.CreateDebugUtilsMessengerEXT(
			vk_instance,
			&debugUtilsCreateInfo,
			nil,
			&vk_debug_utils_messenger,
		)
	}
}
