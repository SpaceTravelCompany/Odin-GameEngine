#+private
package engine

import "base:runtime"
import "core:debug/trace"
import vk "vendor:vulkan"


// ============================================================================
// Resource - Buffer Create/Destroy (No Async)
// ============================================================================

buffer_resource_CreateBufferNoAsync :: #force_inline proc(
	outQueue: ^[dynamic]OpNode,
	buffer: ^buffer_resource,
	option: buffer_create_option,
	data: []byte,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	buffer.option = option
	executeCreateBuffer(outQueue, buffer, data, allocator)
}

buffer_resource_DestroyBufferNoAsync :: proc(self: ^buffer_resource) {
	vk_mem_buffer_UnBindBufferNode(auto_cast self.mem_buffer, self.__resource, self.idx)
	free(self, vk_def_allocator())
}

buffer_resource_DestroyTextureNoAsync :: proc(self: ^texture_resource) {
	vk.DestroyImageView(vk_device, self.img_view, nil)
	vk_mem_buffer_UnBindBufferNode(auto_cast self.mem_buffer, self.__resource, self.idx)
	free(self, vk_def_allocator())
}

buffer_resource_MapCopy :: #force_inline proc(
	base: ^base_resource,
	data: []byte,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	append_op(OpMapCopy{
		p_resource = base,
		data       = data,
		allocator  = allocator,
	})
}


// ============================================================================
// Resource - Execute Create Buffer
// ============================================================================

executeCreateBuffer :: proc(
	outQueue: ^[dynamic]OpNode,
	src: ^buffer_resource,
	data: []byte,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	if src.option.type == .__STAGING {
		src.option.resource_usage = .CPU
		src.option.single = false
	}

	memProp: vk.MemoryPropertyFlags
	switch src.option.resource_usage {
	case .GPU:
		memProp = {.DEVICE_LOCAL}
	case .CPU:
		memProp = {.HOST_CACHED, .HOST_VISIBLE}
	}
	bufUsage: vk.BufferUsageFlags
	switch src.option.type {
	case .VERTEX:
		bufUsage = {.VERTEX_BUFFER}
	case .INDEX:
		bufUsage = {.INDEX_BUFFER}
	case .UNIFORM: //bufUsage = {.UNIFORM_BUFFER} no create each obj
		if src.option.resource_usage == .GPU do trace.panic_log("UNIFORM BUFFER can't resource_usage .GPU")
		bind_uniform_buffer(src, data, allocator)
		return
	case .STORAGE:
		bufUsage = {.STORAGE_BUFFER}
	case .__STAGING:
		bufUsage = {.TRANSFER_SRC}
	}

	bufInfo := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = src.option.size,
		usage       = bufUsage,
		sharingMode = .EXCLUSIVE,
	}

	last: ^buffer_resource
	if data != nil && src.option.resource_usage == .GPU {
		bufInfo.usage |= {.TRANSFER_DST}
		if src.option.size > auto_cast len(data) do trace.panic_log("create_buffer _data not enough size. ", src.option.size, ", ", len(data))

		last = new(buffer_resource, vk_def_allocator())
		buffer_resource_CreateBufferNoAsync(outQueue, last, {
			size           = src.option.size,
			resource_usage = .CPU,
			single         = false,
			type           = .__STAGING,
		}, data, allocator)
	} else if src.option.type == .__STAGING {
		if data == nil do trace.panic_log("staging buffer data can't nil")
	}

	res := vk.CreateBuffer(vk_device, &bufInfo, nil, &src.__resource)
	if res != .SUCCESS do trace.panic_log("res := vk.CreateBuffer(vk_device, &bufInfo, nil, &self.__resource) : ", res)

	src.mem_buffer = auto_cast vk_mem_buffer_CreateFromResourceSingle(src.__resource) if src.option.single else 
	auto_cast vk_mem_buffer_CreateFromResource(src.__resource, memProp, &src.idx, 0, src.option.type)

	if data != nil {
		if src.option.resource_usage != .GPU {
			append_op_save(OpMapCopy{
					p_resource = src,
					data       = data,
				}, outQueue)
		} else {
			//above buffer_resource_CreateBufferNoAsync call, staging buffer is added and map_copy command is added.
			append_op_save(OpCopyBuffer{src = last, target = src, data = data, allocator = allocator}, outQueue)
			//append_op_save(OpDestroyBuffer{src = last}, outQueue) //destroy buffer manually
		}
	}
}

// ============================================================================
// Resource - Execute Create Texture
// ============================================================================

executeCreateTexture :: proc(
	outQueue: ^[dynamic]OpNode,
	src: ^texture_resource,
	data: []byte,
	allocator: Maybe(runtime.Allocator) = nil,
) {
	memProp: vk.MemoryPropertyFlags
	switch src.option.resource_usage {
	case .GPU:
		memProp = {.DEVICE_LOCAL}
	case .CPU:
		memProp = {.HOST_CACHED, .HOST_VISIBLE}
	}
	texUsage: vk.ImageUsageFlags = {}
	isDepth := texture_fmt_is_depth(src.option.format)

	if .IMAGE_RESOURCE in src.option.texture_usage do texUsage |= {.SAMPLED}
	if .FRAME_BUFFER in src.option.texture_usage {
		if isDepth {
			texUsage |= {.DEPTH_STENCIL_ATTACHMENT}
		} else {
			texUsage |= {.COLOR_ATTACHMENT}
		}
	}
	if .__INPUT_ATTACHMENT in src.option.texture_usage do texUsage |= {.INPUT_ATTACHMENT}
	if .__STORAGE_IMAGE in src.option.texture_usage do texUsage |= {.STORAGE}
	if .__TRANSIENT_ATTACHMENT in src.option.texture_usage do texUsage |= {.TRANSIENT_ATTACHMENT}

	tiling: vk.ImageTiling = .OPTIMAL

	if isDepth {
		if (.DEPTH_STENCIL_ATTACHMENT in texUsage && !vkDepthHasOptimal) ||
		   (.SAMPLED in texUsage && !vkDepthHasSampleOptimal) ||
		   (.TRANSFER_SRC in texUsage && !vkDepthHasTransferSrcOptimal) ||
		   (.TRANSFER_DST in texUsage && !vkDepthHasTransferDstOptimal) {
			tiling = .LINEAR
		}
	} else {
		if (.COLOR_ATTACHMENT in texUsage && !vkColorHasAttachOptimal) ||
		   (.SAMPLED in texUsage && !vkColorHasSampleOptimal) ||
		   (.TRANSFER_SRC in texUsage && !vkColorHasTransferSrcOptimal) ||
		   (.TRANSFER_DST in texUsage && !vkColorHasTransferDstOptimal) {
			tiling = .LINEAR
		}
	}
	bit: u32 = auto_cast texture_fmt_bit_size(src.option.format)

	imgInfo := vk.ImageCreateInfo {
		sType         = .IMAGE_CREATE_INFO,
		arrayLayers   = src.option.len,
		usage         = texUsage,
		sharingMode   = .EXCLUSIVE,
		extent        = {width = src.option.width, height = src.option.height, depth = 1},
		samples       = samples_to_vk_sample_count_flags(src.option.samples),
		tiling        = tiling,
		mipLevels     = 1,
		format        = texture_fmt_to_vk_fmt(src.option.format),
		imageType     = texture_type_to_vk_image_type(src.option.type),
		initialLayout = .UNDEFINED,
	}

	last: ^buffer_resource
	if data != nil && src.option.resource_usage == .GPU {
		imgInfo.usage |= {.TRANSFER_DST}

		last = new(buffer_resource, vk_def_allocator())
		buffer_resource_CreateBufferNoAsync(outQueue, last, {
			size           = auto_cast (imgInfo.extent.width * imgInfo.extent.height * imgInfo.extent.depth * imgInfo.arrayLayers * bit),
			resource_usage = .CPU,
			single         = false,
			type           = .__STAGING,
		}, data, allocator)
	}

	res := vk.CreateImage(vk_device, &imgInfo, nil, &src.__resource)
	if res != .SUCCESS do trace.panic_log("res := vk.CreateImage(vk_device, &imgInfo, nil, &src.__resource) : ", res)

	src.mem_buffer = auto_cast vk_mem_buffer_CreateFromResourceSingle(src.__resource) if src.option.single else
	 auto_cast vk_mem_buffer_CreateFromResource(src.__resource, memProp, &src.idx, 0, src.option.type)

	imgViewInfo := vk.ImageViewCreateInfo {
		sType      = .IMAGE_VIEW_CREATE_INFO,
		format     = imgInfo.format,
		components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
		image      = src.__resource,
		subresourceRange = {
			aspectMask     = isDepth ? {.DEPTH, .STENCIL} : {.COLOR},
			baseMipLevel   = 0,
			levelCount     = 1,
			baseArrayLayer = 0,
			layerCount     = imgInfo.arrayLayers,
		},
	}
	switch src.option.type {
	case .TEX2D:
		imgViewInfo.viewType = imgInfo.arrayLayers > 1 ? .D2_ARRAY : .D2
	}

	res = vk.CreateImageView(vk_device, &imgViewInfo, nil, &src.img_view)
	if res != .SUCCESS do trace.panic_log("res = vk.CreateImageView(vk_device, &imgViewInfo, nil, &src.img_view) : ", res)

	if data != nil {
		if src.option.resource_usage != .GPU {
			append_op_save(OpMapCopy{
				p_resource = src,
				data       = data,
				allocator  = allocator,
			}, outQueue)
		} else {
			//above buffer_resource_CreateBufferNoAsync call, staging buffer is added and map_copy command is added.
			append_op_save(OpCopyBufferToTexture{src = last, target = src, data = data, allocator = allocator}, outQueue)
			//append_op_save(OpDestroyBuffer{src = last}, outQueue) //destroy buffer manually
		}
	}
}


// ============================================================================
// Resource - Execute Destroy
// ============================================================================

executeDestroyBuffer :: proc(buf: ^buffer_resource) {
	buffer_resource_DestroyBufferNoAsync(buf)
}

executeDestroyTexture :: proc(tex: ^texture_resource) {
	buffer_resource_DestroyTextureNoAsync(tex)
}


// ============================================================================
// Resource - Execute Copy Operations
// ============================================================================

execute_copy_buffer :: proc(cmd: vk.CommandBuffer, src: ^buffer_resource, target: ^buffer_resource) {
	copyRegion := vk.BufferCopy {
		size      = target.option.size,
		srcOffset = 0,
		dstOffset = 0,
	}
	vk.CmdCopyBuffer(cmd, src.__resource, target.__resource, 1, &copyRegion)
}

execute_copy_buffer_to_texture :: proc(cmd: vk.CommandBuffer, src: ^buffer_resource, target: ^texture_resource) {
	vk_transition_image_layout(cmd, target.__resource, 1, 0, target.option.len, .UNDEFINED, .TRANSFER_DST_OPTIMAL)
	region := vk.BufferImageCopy {
		bufferOffset      = 0,
		bufferRowLength   = 0,
		bufferImageHeight = 0,
		imageOffset       = {x = 0, y = 0, z = 0},
		imageExtent       = {width = target.option.width, height = target.option.height, depth = 1},
		imageSubresource  = {
			aspectMask     = {.COLOR},
			baseArrayLayer = 0,
			mipLevel       = 0,
			layerCount     = target.option.len,
		},
	}
	vk.CmdCopyBufferToImage(cmd, src.__resource, target.__resource, .TRANSFER_DST_OPTIMAL, 1, &region)
	vk_transition_image_layout(cmd, target.__resource, 1, 0, target.option.len, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)
}
