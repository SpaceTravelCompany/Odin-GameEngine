package engine

import "vendor:OpenGL"
import "vendor:wasm/WebGL"


GL_VertexArrayObject :: u32


glCreateVertexArray :: proc() -> GL_VertexArrayObject {
	when is_web {
		return auto_cast(WebGL.CreateVertexArray())
	} else {
		vao: GL_VertexArrayObject
		OpenGL.GenVertexArrays(1, &vao)
		return vao
	}
}

glBindVertexArray :: proc(vao: GL_VertexArrayObject) {
	when is_web {
		WebGL.BindVertexArray(vao)
	} else {
		OpenGL.BindVertexArray(vao)	
	}
}

glDeleteVertexArrays :: proc(arrays: GL_VertexArrayObject) {
	when is_web {
		WebGL.DeleteVertexArray(arrays)
	} else {
		_arrays: [1]GL_VertexArrayObject = {arrays}	
		OpenGL.DeleteVertexArrays(1, &_arrays[0])
	}
}