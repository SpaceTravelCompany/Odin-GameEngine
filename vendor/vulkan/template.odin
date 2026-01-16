package vulkan

import "base:runtime"
import "core:math"
import "core:mem"
import "core:strings"
import "vendor:x11/xlib"


@(rodata) DefaultDynamicStates := [2]DynamicState{DynamicState.VIEWPORT, DynamicState.SCISSOR}
DefaultPipelineDynamicStateCreateInfo : PipelineDynamicStateCreateInfo

@init InitVulkanTemplate :: proc "contextless"() {
	DefaultPipelineDynamicStateCreateInfo = PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = 2,
		pDynamicStates    = &DefaultDynamicStates[0],
	}
	DefaultPipelineColorBlendStateCreateInfo = PipelineColorBlendStateCreateInfo{
		sType = StructureType.PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		pNext = nil,
		flags = {},
		logicOpEnable = false,
		logicOp = LogicOp.COPY, 
		attachmentCount = auto_cast len(__DefaultPipelineColorBlendAttachmentState),
		pAttachments = &__DefaultPipelineColorBlendAttachmentState[0],
		blendConstants = {0,0,0,0},
	}
	
}

@(private="file") __DefaultPipelineColorBlendAttachmentState := [1]PipelineColorBlendAttachmentState{
	PipelineColorBlendAttachmentState{
		blendEnable = true,
		srcColorBlendFactor = BlendFactor.SRC_ALPHA,
		dstColorBlendFactor = BlendFactor.ONE_MINUS_SRC_ALPHA,
		colorBlendOp = BlendOp.ADD,
		srcAlphaBlendFactor = BlendFactor.ONE,
		dstAlphaBlendFactor = BlendFactor.ZERO,
		alphaBlendOp = BlendOp.ADD,
		colorWriteMask = {.R,.G,.B,.A},
	},
}
DefaultPipelineColorBlendStateCreateInfo : PipelineColorBlendStateCreateInfo


DefaultPipelineMultisampleStateCreateInfo := PipelineMultisampleStateCreateInfo{
	sType = StructureType.PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
	rasterizationSamples = {._1},
	sampleShadingEnable = true,
	minSampleShading = 1.0,
	pSampleMask = nil,
	alphaToCoverageEnable = false,
	alphaToOneEnable = false,
	pNext = nil,
	flags = {},
}
DefaultPipelineInputAssemblyStateCreateInfo := PipelineInputAssemblyStateCreateInfo{
	sType = StructureType.PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
	pNext = nil,
	flags = {},
	topology = PrimitiveTopology.TRIANGLE_LIST,
	primitiveRestartEnable = false,
}
DefaultPipelineRasterizationStateCreateInfo := PipelineRasterizationStateCreateInfo{
	sType = StructureType.PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
	polygonMode = .FILL,
	frontFace = .CLOCKWISE,
	cullMode = {},
	depthClampEnable = false,
	rasterizerDiscardEnable = false, 
	depthBiasEnable = false,
	depthBiasConstantFactor = 0.0,
	depthBiasClamp = 0.0,
	depthBiasSlopeFactor = 0.0,
	lineWidth = 1.0,
	pNext = nil,
	flags = {},
}
DefaultPipelineVertexInputStateCreateInfo := PipelineVertexInputStateCreateInfo{
	sType = StructureType.PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	vertexBindingDescriptionCount = 0,
	pVertexBindingDescriptions = nil,
	vertexAttributeDescriptionCount = 0,
	pVertexAttributeDescriptions = nil,
	flags = {},
	pNext = nil,
}
DefaultPipelineDepthStencilStateCreateInfo := PipelineDepthStencilStateCreateInfo{
	depthTestEnable = true,
	depthWriteEnable = true,
	depthBoundsTestEnable = false,
	depthCompareOp = .LESS_OR_EQUAL,
	stencilTestEnable = false,
	front = {},
	back = {},
	maxDepthBounds = 1.0,
	minDepthBounds = 0.0,
	sType = StructureType.PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
}


@(require_results) CreateShaderModule2 :: proc(vkDevice: Device, code: []byte) -> (ShaderModule, Result) {
	code_ := transmute([]u32)code
	createInfo := ShaderModuleCreateInfo {
		codeSize = len(code_),
		pCode    = raw_data(code_),
		sType    = StructureType.SHADER_MODULE_CREATE_INFO,
	}

	shaderModule: ShaderModule
	res := CreateShaderModule(vkDevice, &createInfo, nil, &shaderModule)

	return shaderModule, res
}

@(require_results) CreateShaderStages :: proc "contextless" (
	vertModule: ShaderModule,
	fragModule: ShaderModule,
) -> [2]PipelineShaderStageCreateInfo {
	return [2]PipelineShaderStageCreateInfo {
		PipelineShaderStageCreateInfo {
			sType = StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO,
			pName = "main",
			module = vertModule,
			stage = {.VERTEX},
		},
		PipelineShaderStageCreateInfo {
			sType = StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO,
			pName = "main",
			module = fragModule,
			stage = {.FRAGMENT},
		},
	}
}

@(require_results) CreateShaderStagesGS :: proc "contextless" (
	vertModule: ShaderModule,
	fragModule: ShaderModule,
	geomModule: ShaderModule,
) -> [3]PipelineShaderStageCreateInfo {
	return [3]PipelineShaderStageCreateInfo {
		PipelineShaderStageCreateInfo {
			sType = StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO,
			pName = "main",
			module = vertModule,
			stage = {.VERTEX},
		},
		PipelineShaderStageCreateInfo {
			sType = StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO,
			pName = "main",
			module = geomModule,
			stage = {.GEOMETRY},
		},
		PipelineShaderStageCreateInfo {
			sType = StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO,
			pName = "main",
			module = fragModule,
			stage = {.FRAGMENT},
		},
	}
}

@(require_results) DescriptorSetLayoutBindingInit :: proc "contextless"(
	binding: u32,
	descriptorCount: u32,
	descriptorType: DescriptorType = .UNIFORM_BUFFER,
	stageFlags: ShaderStageFlags = {.VERTEX, .FRAGMENT},
	pImmutableSampler: ^Sampler = nil,
) -> DescriptorSetLayoutBinding {
	return {
		binding = binding,
		descriptorCount = descriptorCount,
		descriptorType = descriptorType,
		stageFlags = stageFlags,
		pImmutableSamplers = pImmutableSampler,
	}
}

@(require_results) DescriptorSetLayoutInit :: proc "contextless"(
	vkDevice: Device, bindings: []DescriptorSetLayoutBinding,
) -> DescriptorSetLayout {
	setLayoutInfo := DescriptorSetLayoutCreateInfo {
		bindingCount = auto_cast len(bindings),
		pBindings    = raw_data(bindings),
		sType        = StructureType.DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
	}
	descriptorSetLayout: DescriptorSetLayout
	CreateDescriptorSetLayout(vkDevice, &setLayoutInfo, nil, &descriptorSetLayout)

	return descriptorSetLayout
}


@(require_results) PipelineLayoutInit :: proc "contextless"(vkDevice: Device, sets: []DescriptorSetLayout) -> PipelineLayout {
	pipelineLayoutInfo := PipelineLayoutCreateInfo {
		setLayoutCount = auto_cast len(sets),
		pSetLayouts    = raw_data(sets),
		sType          = StructureType.PIPELINE_LAYOUT_CREATE_INFO,
	}
	pipelineLayout: PipelineLayout
	CreatePipelineLayout(vkDevice, &pipelineLayoutInfo, nil, &pipelineLayout)

	return pipelineLayout
}

@(require_results) StencilOpStateInit :: proc "contextless"(
	compareOp: CompareOp,
	depthFailOp: StencilOp,
	passOp: StencilOp,
	failOp: StencilOp,
	compareMask: u32 = 0xff,
	writeMask: u32 = 0xff,
	reference: u32 = 0xff,
) -> StencilOpState {
	return {
		compareOp = compareOp,
		depthFailOp = depthFailOp,
		passOp = passOp,
		failOp = failOp,
		compareMask = compareMask,
		writeMask = writeMask,
		reference = reference,
	}
}

@(require_results) PipelineDepthStencilStateCreateInfoInit :: proc "contextless"(
	depthTestEnable: b32 = true,
	depthWriteEnable: b32 = true,
	depthBoundsTestEnable: b32 = false,
	depthCompareOp: CompareOp = CompareOp.LESS_OR_EQUAL,
	stencilTestEnable: b32 = false,
	front: StencilOpState = {},
	back: StencilOpState = {},
	maxDepthBounds: f32 = 0,
	minDepthBounds: f32 = 0,
) -> PipelineDepthStencilStateCreateInfo {
	return {
		depthTestEnable = depthTestEnable,
		depthWriteEnable = depthWriteEnable,
		depthBoundsTestEnable = depthBoundsTestEnable,
		depthCompareOp = depthCompareOp,
		stencilTestEnable = stencilTestEnable,
		front = front,
		back = back,
		maxDepthBounds = maxDepthBounds,
		minDepthBounds = minDepthBounds,
		sType = StructureType.PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
	}
}

@(require_results) PipelineInputAssemblyStateCreateInfoInit :: proc "contextless"(
	topology: PrimitiveTopology =  PrimitiveTopology.TRIANGLE_LIST,
	primitiveRestartEnable: b32 = false,
	pNext: rawptr = nil,
	flags: PipelineInputAssemblyStateCreateFlags = {},
) -> PipelineInputAssemblyStateCreateInfo {
	return {
		sType = StructureType.PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		pNext = pNext,
		flags = flags,
		topology = topology,
		primitiveRestartEnable = primitiveRestartEnable,
	}
}

@(require_results) PipelineViewportStateCreateInfoInit :: proc "contextless"(
	viewportCount: u32 = 1,
	pViewports:    [^]Viewport = nil,
	scissorCount:  u32 = 1,
	pScissors:     [^]Rect2D = nil,
	flags:         PipelineViewportStateCreateFlags = {},
	pNext:         rawptr = nil,
) -> PipelineViewportStateCreateInfo {
	return {
		sType = StructureType.PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = viewportCount,
		pViewports = pViewports,
		scissorCount = scissorCount,
		pScissors = pScissors,
		flags = flags,
		pNext = pNext,
	}
}

@(require_results) PipelineVertexInputStateCreateInfoInit :: proc "contextless"(
	pVertexBindingDescriptions:Maybe([]VertexInputBindingDescription) = nil,
	pVertexAttributeDescriptions:Maybe([]VertexInputAttributeDescription) = nil,
	flags:         PipelineVertexInputStateCreateFlags = {},
	pNext:         rawptr = nil,
) -> PipelineVertexInputStateCreateInfo {
	return {
		sType = StructureType.PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount = 0 if pVertexBindingDescriptions == nil else auto_cast len(pVertexBindingDescriptions.?),
		pVertexBindingDescriptions = raw_data(pVertexBindingDescriptions.?) if pVertexBindingDescriptions != nil && len(pVertexBindingDescriptions.?) > 0 else nil,
		vertexAttributeDescriptionCount = 0 if pVertexAttributeDescriptions == nil else auto_cast len(pVertexAttributeDescriptions.?),
		pVertexAttributeDescriptions = raw_data(pVertexAttributeDescriptions.?) if pVertexAttributeDescriptions != nil && len(pVertexAttributeDescriptions.?) > 0 else nil,
		flags = flags,
		pNext = pNext,
	}
}



@(require_results) GraphicsPipelineCreateInfoInit :: proc "contextless"(
	stages: []PipelineShaderStageCreateInfo,
	layout: PipelineLayout,
	renderPass: RenderPass,
	pVertexInputState: ^PipelineVertexInputStateCreateInfo = nil,
	pInputAssemblyState: ^PipelineInputAssemblyStateCreateInfo = nil,
	pTessellationState: ^PipelineTessellationStateCreateInfo = nil,
	pViewportState: ^PipelineViewportStateCreateInfo = nil,
	pRasterizationState: ^PipelineRasterizationStateCreateInfo = nil,
	pMultisampleState: ^PipelineMultisampleStateCreateInfo = nil,
	pDepthStencilState: ^PipelineDepthStencilStateCreateInfo = nil,
	pColorBlendState: ^PipelineColorBlendStateCreateInfo = nil,
	pDynamicState: ^PipelineDynamicStateCreateInfo = nil,
	subpass: u32 = 0,
	basePipelineHandle: Pipeline = 0,
	basePipelineIndex: i32 = -1,
) -> GraphicsPipelineCreateInfo {
	return {
		stageCount = auto_cast len(stages),
		pStages = raw_data(stages),
		pVertexInputState = pVertexInputState if pVertexInputState != nil else &DefaultPipelineVertexInputStateCreateInfo,
		pInputAssemblyState = pInputAssemblyState if pInputAssemblyState != nil else &DefaultPipelineInputAssemblyStateCreateInfo,
		pTessellationState = pTessellationState,
		pViewportState = pViewportState if pViewportState != nil else nil,
		pRasterizationState = pRasterizationState if pRasterizationState != nil else &DefaultPipelineRasterizationStateCreateInfo,
		pMultisampleState = pMultisampleState if pMultisampleState != nil else &DefaultPipelineMultisampleStateCreateInfo,
		pDepthStencilState = pDepthStencilState,
		pColorBlendState = pColorBlendState if pColorBlendState != nil else &DefaultPipelineColorBlendStateCreateInfo,
		pDynamicState = pDynamicState if pDynamicState != nil else &DefaultPipelineDynamicStateCreateInfo,
		layout = layout,
		renderPass = renderPass,
		subpass = subpass,
		basePipelineHandle = basePipelineHandle,
		basePipelineIndex = basePipelineIndex,
		sType = StructureType.GRAPHICS_PIPELINE_CREATE_INFO,
		pNext = nil,
		flags = {},
	}
}

@(require_results) AttachmentDescriptionInit :: proc "contextless"(
	format: Format,
	loadOp: AttachmentLoadOp = .DONT_CARE,
	storeOp: AttachmentStoreOp = .DONT_CARE,
	initialLayout: ImageLayout = .UNDEFINED,
	finalLayout: ImageLayout = .UNDEFINED,
	stencilLoadOp: AttachmentLoadOp = .DONT_CARE,
	stencilStoreOp: AttachmentStoreOp = .DONT_CARE,
	samples: SampleCountFlags = {SampleCountFlag._1},
) -> AttachmentDescription {
	return {
		loadOp = loadOp,
		storeOp = storeOp,
		initialLayout = initialLayout,
		finalLayout = finalLayout,
		stencilLoadOp = stencilLoadOp,
		stencilStoreOp = stencilStoreOp,
		samples = samples,
		format = format,
	}
}

@(require_results) RenderPassCreateInfoInit :: proc "contextless"(
	pAttachments: []AttachmentDescription,
	pSubpasses: []SubpassDescription,
	pDependencies: []SubpassDependency,
) -> RenderPassCreateInfo {
	return {
		sType = StructureType.RENDER_PASS_CREATE_INFO,
		attachmentCount = auto_cast len(pAttachments),
		pAttachments = &pAttachments[0],
		subpassCount = auto_cast len(pSubpasses),
		pSubpasses = &pSubpasses[0],
		dependencyCount = auto_cast len(pDependencies),
		pDependencies = &pDependencies[0],
	}
}

@(require_results) PipelineRasterizationStateCreateInfoInit :: proc "contextless"(
	polygonMode:             PolygonMode = PolygonMode.FILL,
	frontFace:               FrontFace = FrontFace.CLOCKWISE,
	cullMode:                CullModeFlags = {},
	depthClampEnable:        b32 = false,
	rasterizerDiscardEnable: b32 = false,
	depthBiasEnable:         b32 = false,
	depthBiasConstantFactor: f32 = 0.0,
	depthBiasClamp:          f32 = 0.0,
	depthBiasSlopeFactor:    f32 = 0.0,
	lineWidth:               f32 = 1.0,
	pNext:                   rawptr = nil,
	flags:                   PipelineRasterizationStateCreateFlags = {},
) -> PipelineRasterizationStateCreateInfo {
	return {
		sType = StructureType.PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = polygonMode,
		frontFace = frontFace,
		cullMode = cullMode,
		depthClampEnable = depthClampEnable,
		rasterizerDiscardEnable = rasterizerDiscardEnable, 
		depthBiasEnable = depthBiasEnable,
		depthBiasConstantFactor = depthBiasConstantFactor,
		depthBiasClamp = depthBiasClamp,
		depthBiasSlopeFactor = depthBiasSlopeFactor,
		lineWidth = lineWidth,
		pNext = pNext,
		flags = flags,
	}
}

@(require_results) PipelineMultisampleStateCreateInfoInit :: proc "contextless"(
	rasterizationSamples:  SampleCountFlags = {._1},
	sampleShadingEnable:   b32 = true,
	minSampleShading:      f32 = 1.0,
	pSampleMask:           ^SampleMask = nil,
	alphaToCoverageEnable: b32 = false,
	alphaToOneEnable:      b32 = false,
    pNext:                 rawptr = nil,
	flags:                 PipelineMultisampleStateCreateFlags = {},
) -> PipelineMultisampleStateCreateInfo {
	return {
		sType = StructureType.PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        rasterizationSamples = rasterizationSamples,
        sampleShadingEnable = sampleShadingEnable,
        minSampleShading = minSampleShading,
        pSampleMask = pSampleMask,
        alphaToCoverageEnable = alphaToCoverageEnable,
        alphaToOneEnable = alphaToOneEnable,
        pNext = pNext,
        flags = flags,
	}
}

@(require_results) PipelineColorBlendAttachmentStateInit :: proc "contextless"(
	blendEnable:         b32 = true,
	srcColorBlendFactor: BlendFactor = BlendFactor.SRC_ALPHA,
	dstColorBlendFactor: BlendFactor = BlendFactor.ONE_MINUS_SRC_ALPHA,
	colorBlendOp:        BlendOp = BlendOp.ADD,
	srcAlphaBlendFactor: BlendFactor = BlendFactor.ONE,
	dstAlphaBlendFactor: BlendFactor = BlendFactor.ZERO,
	alphaBlendOp:        BlendOp = BlendOp.ADD,
	colorWriteMask:      ColorComponentFlags = {.R,.G,.B,.A},
) -> PipelineColorBlendAttachmentState {
	return {
		blendEnable = blendEnable,
		srcColorBlendFactor = srcColorBlendFactor,
		dstColorBlendFactor = dstColorBlendFactor,
		colorBlendOp = colorBlendOp,
		srcAlphaBlendFactor = srcAlphaBlendFactor,
		dstAlphaBlendFactor = dstAlphaBlendFactor,
		alphaBlendOp = alphaBlendOp,
		colorWriteMask = colorWriteMask,
	}
}

@(require_results) PipelineColorBlendStateCreateInfoInit :: proc "contextless"(
	pAttachments:    []PipelineColorBlendAttachmentState,
	logicOpEnable:   b32 = false,
	logicOp:         LogicOp = LogicOp.COPY,
	blendConstants:  [4]f32 = {0,0,0,0},
	flags:           PipelineColorBlendStateCreateFlags = {},
	pNext:           rawptr = nil,
) -> PipelineColorBlendStateCreateInfo {
	return {
		sType = StructureType.PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		pNext = pNext,
		flags = flags,
		logicOpEnable = logicOpEnable,
		logicOp = logicOp, 
		attachmentCount = auto_cast len(pAttachments),
		pAttachments = raw_data(pAttachments),
		blendConstants = blendConstants,
	}
}
