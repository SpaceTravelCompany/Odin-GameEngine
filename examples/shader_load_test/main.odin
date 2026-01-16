package shader_load_test

import "core:fmt"

main :: proc() {
	// Test different optimization levels
	vert_none := #shader_load("test.vert")                    // default: no optimization
	vert_size := #shader_load("test.vert", "size")            // -Os: size optimization
	vert_speed := #shader_load("test.vert", "speed")          // -O: speed optimization
	
	frag_none := #shader_load("test.frag")
	frag_speed := #shader_load("test.frag", "speed")
	
	fmt.println("=== Vertex Shader ===")
	fmt.println("  No optimization:", len(vert_none), "bytes")
	fmt.println("  Size optimized: ", len(vert_size), "bytes")
	fmt.println("  Speed optimized:", len(vert_speed), "bytes")
	
	fmt.println("\n=== Fragment Shader ===")
	fmt.println("  No optimization:", len(frag_none), "bytes")
	fmt.println("  Speed optimized:", len(frag_speed), "bytes")
	
	// Verify SPIR-V magic number (0x07230203)
	if len(vert_none) >= 4 {
		magic := (cast([^]u32)raw_data(vert_none))[0]
		fmt.printf("\nSPIR-V magic number: 0x%08X (expected: 0x07230203)\n", magic)
	}
}
