#+private
package engine

import "core:debug/trace"
import vk "vendor:vulkan"


// ============================================================================
// Render Pass - Create Render Pass
// ============================================================================

vk_create_render_pass :: proc() {
	vk_depth_fmt := texture_fmt_to_vk_fmt(depth_fmt)
	depthAttachmentSample := vk.AttachmentDescriptionInit(
		format = vk_depth_fmt,
		loadOp = .CLEAR,
		storeOp = .STORE,
		initialLayout = .UNDEFINED,
		finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		samples = VK_SAMPLE_COUNT_FLAGS,
	)

	colorAttachmentSample := vk.AttachmentDescriptionInit(
		format = vk_fmt.format,
		loadOp = .CLEAR,
		storeOp = .STORE,
		initialLayout = .UNDEFINED,
		finalLayout = .COLOR_ATTACHMENT_OPTIMAL,
		samples = VK_SAMPLE_COUNT_FLAGS,
	)
	colorAttachmentResolve := vk.AttachmentDescriptionInit(
		format = vk_fmt.format,
		storeOp = .STORE,
		finalLayout = .PRESENT_SRC_KHR,
	)

	colorAttachmentLoadResolve := vk.AttachmentDescriptionInit(
		format = vk_fmt.format,
		loadOp = .LOAD,
		initialLayout = .COLOR_ATTACHMENT_OPTIMAL,
		finalLayout = .COLOR_ATTACHMENT_OPTIMAL,
	)

	colorAttachment := vk.AttachmentDescriptionInit(
		format = vk_fmt.format,
		loadOp = .CLEAR,
		storeOp = .STORE,
		finalLayout = .PRESENT_SRC_KHR,
	)
	depthAttachment := vk.AttachmentDescriptionInit(
		format = vk_depth_fmt,
		loadOp = .CLEAR,
		storeOp = .STORE,
		finalLayout = .PRESENT_SRC_KHR,
	)
	shapeBackAttachment := vk.AttachmentDescriptionInit(
		format = .R8_UNORM,
		loadOp = .CLEAR,
		storeOp = .DONT_CARE,
		finalLayout = .GENERAL,
		initialLayout = .GENERAL,
	)

	colorAttachmentRef := vk.AttachmentReference {
		attachment = 0,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}
	colorResolveAttachmentRef := vk.AttachmentReference {
		attachment = 2,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}
	depthAttachmentRef := vk.AttachmentReference {
		attachment = 1,
		layout     = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
	}
	inputAttachmentRef := vk.AttachmentReference {
		attachment = 1,
		layout     = .SHADER_READ_ONLY_OPTIMAL,
	}


	subpassDesc := vk.SubpassDescription {
		pipelineBindPoint       = .GRAPHICS,
		colorAttachmentCount    = 1,
		pColorAttachments       = &colorAttachmentRef,
		pDepthStencilAttachment = &depthAttachmentRef,
	}
	subpassResolveDesc := vk.SubpassDescription {
		pipelineBindPoint       = .GRAPHICS,
		colorAttachmentCount    = 1,
		pColorAttachments       = &colorAttachmentRef,
		pDepthStencilAttachment = &depthAttachmentRef,
		pResolveAttachments = &colorResolveAttachmentRef,
	}
	subpassCopyDesc := vk.SubpassDescription {
		pipelineBindPoint    = .GRAPHICS,
		colorAttachmentCount = 1,
		inputAttachmentCount = 1,
		pColorAttachments    = &colorAttachmentRef,
		pInputAttachments    = &inputAttachmentRef,
	}

	subpassDependency := vk.SubpassDependency {
		srcSubpass    = vk.SUBPASS_EXTERNAL,
		dstSubpass    = 0,
		srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS},
		srcAccessMask = {},
		dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS},
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE, .DEPTH_STENCIL_ATTACHMENT_WRITE},
	}
	subpassDependencyCopy := vk.SubpassDependency {
		srcSubpass    = vk.SUBPASS_EXTERNAL,
		dstSubpass    = 0,
		srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		srcAccessMask = {},
		dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
	}

	when msaa_count == 1 {
		renderPassInfo := vk.RenderPassCreateInfoInit(
			pAttachments = []vk.AttachmentDescription{colorAttachment, depthAttachment},
			pSubpasses = []vk.SubpassDescription{subpassDesc},
			pDependencies = []vk.SubpassDependency{subpassDependency},
		)
	} else {
		renderPassInfo := vk.RenderPassCreateInfoInit(
			pAttachments = []vk.AttachmentDescription{colorAttachmentSample, depthAttachmentSample, colorAttachmentResolve},
			pSubpasses = []vk.SubpassDescription{subpassResolveDesc},
			pDependencies = []vk.SubpassDependency{subpassDependency},
		)
	}
	
	vk.CreateRenderPass(vk_device, &renderPassInfo, nil, &vk_render_pass)
}
