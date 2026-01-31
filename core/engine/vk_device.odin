#+private
package engine


import "core:fmt"
import "core:mem"
import vk "vendor:vulkan"
import "core:log"


// ============================================================================
// Physical Device Selection
// ============================================================================

vk_select_physical_device :: proc() {
	physicalDeviceCnt: u32
	vk.EnumeratePhysicalDevices(vk_instance, &physicalDeviceCnt, nil)
	vk_physical_devices := mem.make_non_zeroed([]vk.PhysicalDevice, physicalDeviceCnt, context.temp_allocator)
	defer delete(vk_physical_devices, context.temp_allocator)
	vk.EnumeratePhysicalDevices(vk_instance, &physicalDeviceCnt, &vk_physical_devices[0])

	out: for pd in vk_physical_devices {
		queueFamilyPropCnt: u32
		vk.GetPhysicalDeviceQueueFamilyProperties(pd, &queueFamilyPropCnt, nil)
		queueFamilies := mem.make_non_zeroed([]vk.QueueFamilyProperties, queueFamilyPropCnt, context.temp_allocator)
		defer delete(queueFamilies, context.temp_allocator)
		vk.GetPhysicalDeviceQueueFamilyProperties(pd, &queueFamilyPropCnt, &queueFamilies[0])

		for i in 0 ..< queueFamilyPropCnt {
			if .GRAPHICS in queueFamilies[i].queueFlags do vk_graphics_family_index = i
			
			isPresentSupport: b32
			vk.GetPhysicalDeviceSurfaceSupportKHR(pd, i, vk_surface, &isPresentSupport)

			if isPresentSupport do vk_present_family_index = i
			if vk_graphics_family_index != max(u32) && vk_present_family_index != max(u32) {
				vk_physical_device = pd
				break out
			}
		}
	}
}


// ============================================================================
// Logical Device Creation
// ============================================================================

vk_create_logical_device :: proc() {
	queuePriorty: [1]f32 = {1}
	deviceQueueCreateInfos := [2]vk.DeviceQueueCreateInfo {
		vk.DeviceQueueCreateInfo {
			sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
			queueCount = 1,
			queueFamilyIndex = vk_graphics_family_index,
			pQueuePriorities = &queuePriorty[0],
		},
		vk.DeviceQueueCreateInfo {
			sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
			queueCount = 1,
			queueFamilyIndex = vk_present_family_index,
			pQueuePriorities = &queuePriorty[0],
		},
	}
	queueCnt: u32 = 1 if vk_graphics_family_index == vk_present_family_index else 2

	deviceExtCnt: u32
	vk.EnumerateDeviceExtensionProperties(vk_physical_device, nil, &deviceExtCnt, nil)
	deviceExts := mem.make_non_zeroed([]vk.ExtensionProperties, deviceExtCnt, context.temp_allocator)
	defer delete(deviceExts, context.temp_allocator)
	vk.EnumerateDeviceExtensionProperties(vk_physical_device, nil, &deviceExtCnt, &deviceExts[0])

	deviceExtNames := mem.make_non_zeroed([dynamic]cstring, 0, len(DEVICE_EXTENSIONS) + 1, context.temp_allocator)
	defer delete(deviceExtNames)
	non_zero_append(&deviceExtNames, vk.KHR_SWAPCHAIN_EXTENSION_NAME)

	for &e in deviceExts {
		for _, i in DEVICE_EXTENSIONS {
			if !DEVICE_EXTENSIONS_CHECK[i] &&
			   mem.compare((transmute([^]byte)DEVICE_EXTENSIONS[i])[:len(DEVICE_EXTENSIONS[i])],e.extensionName[:len(DEVICE_EXTENSIONS[i])]) == 0 {
				non_zero_append(&deviceExtNames, DEVICE_EXTENSIONS[i])
				DEVICE_EXTENSIONS_CHECK[i] = true
				log.infof("SYSLOG : vulkan %s device ext support\n", DEVICE_EXTENSIONS[i])
			}
		}
	}

	//TODO: Check Vulkan Compatibility
	REQUIRED_VK_13_FEATURES := vk.PhysicalDeviceVulkan13Features {
		sType            = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		//dynamicRendering = true,
		//synchronization2 = true,
		shaderDemoteToHelperInvocation = true,
	}
	REQUIRED_VK_12_FEATURES := vk.PhysicalDeviceVulkan12Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		timelineSemaphore = true,
		vulkanMemoryModel = true,
		vulkanMemoryModelDeviceScope = true,
		bufferDeviceAddress = true,
		storageBuffer8BitAccess = true,
		scalarBlockLayout = true,
	}
	REQUIRED_VK_RAY_QUERY_FEATURES := vk.PhysicalDeviceRayQueryFeaturesKHR  {
		sType = .PHYSICAL_DEVICE_RAY_QUERY_FEATURES_KHR,
		rayQuery = true,
	}
	if get_vulkan_version().major > 1 || get_vulkan_version().minor >= 3 {
		REQUIRED_VK_RAY_QUERY_FEATURES.pNext = &REQUIRED_VK_13_FEATURES
	}
	REQUIRED_VK_11_FEATURES := vk.PhysicalDeviceVulkan11Features {
		sType                         = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
		//variablePointers              = true,
		//variablePointersStorageBuffer = true,
	}
	if get_vulkan_version().major > 1 || get_vulkan_version().minor >= 2 {
		REQUIRED_VK_11_FEATURES.pNext = &REQUIRED_VK_12_FEATURES
		REQUIRED_VK_12_FEATURES.pNext = &REQUIRED_VK_RAY_QUERY_FEATURES
	}
	REQUIRED_FEATURES := vk.PhysicalDeviceFeatures2 {
		sType    = .PHYSICAL_DEVICE_FEATURES_2,
		features = {
			samplerAnisotropy = true,
			vertexPipelineStoresAndAtomics = true,
			shaderInt64 = true,
			fragmentStoresAndAtomics = true,
		},
	}
	if get_vulkan_version().major > 1 || get_vulkan_version().minor >= 1 do REQUIRED_FEATURES.pNext = &REQUIRED_VK_11_FEATURES

	deviceCreateInfo := vk.DeviceCreateInfo {
		sType                   = vk.StructureType.DEVICE_CREATE_INFO,
		pQueueCreateInfos       = &deviceQueueCreateInfos[0],
		queueCreateInfoCount    = queueCnt,
		pEnabledFeatures        = nil,
		ppEnabledExtensionNames = &deviceExtNames[0],
		enabledExtensionCount   = auto_cast len(deviceExtNames),
		pNext = &REQUIRED_FEATURES,
	}

	res := vk.CreateDevice(vk_physical_device, &deviceCreateInfo, nil, &vk_device)
	if (res != vk.Result.SUCCESS) do log.panicf("res = vk.CreateDevice(vk_physical_device, &deviceCreateInfo, nil, &vk_device) : %s\n", res)
	vk.load_proc_addresses_device(vk_device)

	vk.GetPhysicalDeviceMemoryProperties(vk_physical_device, &vk_physical_mem_prop)
	vk.GetPhysicalDeviceProperties(vk_physical_device, &vk_physical_prop)

	if vk_graphics_family_index == vk_present_family_index {
		vk.GetDeviceQueue(vk_device, vk_graphics_family_index, 0, &vk_graphics_queue)
		vk_present_queue = vk_graphics_queue
	} else {
		vk.GetDeviceQueue(vk_device, vk_graphics_family_index, 0, &vk_graphics_queue)
		vk.GetDeviceQueue(vk_device, vk_present_family_index, 0, &vk_present_queue)
	}

	res = vk.CreateCommandPool(vk_device, &vk.CommandPoolCreateInfo{
		sType = vk.StructureType.COMMAND_POOL_CREATE_INFO,
		flags = vk.CommandPoolCreateFlags{.RESET_COMMAND_BUFFER},
		queueFamilyIndex = vk_graphics_family_index,
	}, nil, &vk_cmd_pool)
	if res != .SUCCESS do log.panicf("vk.CreateCommandPool(&vk_cmd_pool) : %s\n", res)

	res = vk.AllocateCommandBuffers(vk_device, &vk.CommandBufferAllocateInfo{
		sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool = vk_cmd_pool,
		level = vk.CommandBufferLevel.PRIMARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}, &vk_cmd_buffer[0])
	if res != .SUCCESS do log.panicf("vk.AllocateCommandBuffers(&vk_cmd_buffer) : %s\n", res)
}
