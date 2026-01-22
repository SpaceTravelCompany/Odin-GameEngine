package build_tool

import "core:fmt"
import "core:encoding/json"
import "core:mem"
import "core:slice"
import "core:os"
import "core:os/os2"
import "core:strings"
import "core:sys/linux"
import "core:path/filepath"


read_build_json :: proc() -> (json.Value, bool) {
	f, ok := os.read_entire_file("build.json")
	if(!ok) {
		fmt.eprintln("err: not found build.json!")
		return nil, false
	}
	//fmt.println(string(f))
	defer delete(f)

	json_data, json_err  := json.parse(f)
	if(json_err != .None) {
		fmt.eprintln("err: json ", json_err)
		return nil, false
	}
	return json_data, true
}

/*
arm-linux-gnueabi
aarch64-linux-gnu
i686-linux-gnu
x86_64-linux-gnu
riscv64-linux-gnu
*/


main :: proc() {
	//shader compile only
	// if len(os2.args) >= 2 {
	// 	if os2.args[1] == "-s" || os2.args[1] == "--shader" {
	// 		findGLSLFileAndRunCmd()
	// 		return
	// 	}
	// }

	//fmt.println(os.args)
	json_data:json.Value
	ok :bool

	if json_data, ok = read_build_json() ; !ok {return}
	defer json.destroy_value(json_data)
	//fmt.println(json_data)

	setting := (json_data.(json.Object)["setting"]).(json.Object)

	is_android :bool = false
	if "is-android" in setting {
		is_android = setting["is-android"].(json.Boolean)
	}
	log :bool = false
	if "log" in setting {
		log = setting["log"].(json.Boolean)
	}

	// Sets the optimization mode for compilation.
	// Available options:
	// 		-o:none
	// 		-o:minimal
	// 		-o:size
	// 		-o:speed
	// 		-o:aggressive (use this with caution)
	// The default is -o:minimal.


	os.make_directory("bin")
	o:string
	debug:bool = false
	if strings.compare(setting["build-type"].(json.String), "minimal") == 0 {
		o = "-o:minimal"
		debug = true
	} else {
		o = strings.join({"-o:", setting["build-type"].(json.String)}, "", context.temp_allocator)
	}
	defer free_all(	context.temp_allocator)

	//if !findGLSLFileAndRunCmd() do return

	if is_android {
		android_options := (json_data.(json.Object)["android"]).(json.Object)
		os2.make_directory("android")
		os2.make_directory("android/lib")
		os2.make_directory("android/lib/lib")

		os2.make_directory("android/lib/lib/arm64-v8a")

		
		ndkPath := android_options["ndk"].(json.String)
		sdkPath := android_options["sdk"].(json.String)
		export_vulkan_validation_layer := false
		if "export_vulkan_validation_layer" in android_options && debug {
			export_vulkan_validation_layer = android_options["export_vulkan_validation_layer"].(json.Boolean)
		}
		keystore := "android/debug.keystore"
		keystore_password := "android"
		if "keystore" in android_options {
			keystore = android_options["keystore"].(json.String)
		}
		if "keystore-password" in android_options {
			keystore_password = android_options["keystore-password"].(json.String)
		}

		PLATFORM := android_options["platform-version"].(json.String)
		//!use build-tools version same as platform version

		toolchainPath : string
		os2.set_env("ODIN_ANDROID_SDK", sdkPath)
		os2.set_env("ODIN_ANDROID_NDK", ndkPath)
		when ODIN_OS == .Windows {
			toolchainPath = strings.join({ndkPath, "/toolchains/llvm/prebuilt/windows-x86_64"}, "", context.temp_allocator)
		} else when ODIN_OS == .Linux {
			toolchainPath = strings.join({ndkPath, "/toolchains/llvm/prebuilt/linux-x86_64"}, "", context.temp_allocator)
		} else {
			#panic("Unsupported OS for Android build")
		}
		os2.set_env("ODIN_ANDROID_NDK_TOOLCHAIN", toolchainPath)

		// err := os2.copy_file("android/lib/lib/arm64-v8a/libc++_shared.so", filepath.join({toolchainPath, "/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"}, context.temp_allocator))
		// if err != nil {
		// 	fmt.panicf("libc++_shared copy_file: %s", err)
		// }

		if export_vulkan_validation_layer {
			err := os2.copy_file("android/lib/lib/arm64-v8a/libVkLayer_khronos_validation.so", filepath.join({ODIN_ROOT, "/core/engine/lib/android/libVkLayer_khronos_validation_arm64.so"}, context.temp_allocator))
			if err != nil {
				fmt.panicf("libVkLayer_khronos_validation copy_file: %s", err)
			}
		}
		// os2.make_directory("android/lib/lib/armeabi-v7a")//!only supports arm64 now
		// os2.make_directory("android/lib/lib/x86_64")
		// os2.make_directory("android/lib/lib/x86")
		// os2.make_directory("android/lib/lib/riscv64")

		targets :[]string = {
			"-target:linux_arm64",
			"-target:linux_arm32",
			"-target:linux_amd64",
			"-target:linux_i386",
			"-target:linux_riscv64",
		}
		outSos :[]string = {
			strings.join({"android/lib/lib/arm64-v8a/lib", setting["main-package"].(json.String), ".so"}, "", context.temp_allocator),
			strings.join({"android/lib/lib/armeabi-v7a/lib", setting["main-package"].(json.String), ".so"}, "", context.temp_allocator),
			strings.join({"android/lib/lib/x86_64/lib", setting["main-package"].(json.String), ".so"}, "", context.temp_allocator),
			strings.join({"android/lib/lib/x86/lib", setting["main-package"].(json.String), ".so"}, "", context.temp_allocator),
			strings.join({"android/lib/lib/riscv64/lib", setting["main-package"].(json.String), ".so"}, "", context.temp_allocator),
		}


		builded := false

		
		
		for target, i in targets {
			if !runCmd({"odin", "build", 
			setting["main-package"].(json.String), 
			"-no-bounds-check" if !debug else ({}),
			strings.join({"-out:", outSos[i]}, "", context.temp_allocator), 
			o, 
			"-debug" if debug else ({}),
			"-define:LOG=true" if log else "-define:LOG=false",
			//"-show-system-calls" if debug else ({}),
			//"-sanitize:address" if debug else ({}),
			"-build-mode:shared",
			target,
			"-subtarget:android",
			//"-show-debug-messages",//!for debug
			fmt.aprint("-minimum-os-version:", PLATFORM, sep = "", allocator = context.temp_allocator),
			//"-extra-linker-flags:\"-L lib/lib/arm64-v8a -lVkLayer_khronos_validation\"" if debug else ({}),
			}) {
				return
			}

			//?"$ANDROID_JBR/bin/keytool" -genkey -v -keystore .keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000
			keystore_cmd := strings.join({"-android-keystore:", keystore}, "", context.temp_allocator)
			keystore_password_cmd := strings.join({"-android-keystore-password:", keystore_password}, "", context.temp_allocator)
			if !runCmd({"odin", "bundle", "android", "android", keystore_cmd, keystore_password_cmd,
			}) {
				return
			}

			builded = true

			os2.copy_file(strings.join({setting["out-path"].(json.String), ".apk"}, "", context.temp_allocator),
				"test.apk")

			break//!only supports arm64 now
		}
		if export_vulkan_validation_layer {
			os2.remove("android/lib/lib/arm64-v8a/libVkLayer_khronos_validation.so")
		}

		if builded {
			os2.remove("test.apk")
			os2.remove("test.apk-build")
			os2.remove("test.apk.idsig")
		}	
	} else {
		target_arch :string = ""
		if "target-arch" in setting && ODIN_OS == .Linux {
			target_arch_str := setting["target-arch"].(json.String)
			switch target_arch_str {
			case "arm64":
				target_arch = "-target:linux_arm64"
			case "amd64":
				target_arch = "-target:linux_amd64"
			case "i386":
				target_arch = "-target:linux_i386"
			case "riscv64":
				target_arch = "-target:linux_riscv64"
			case "native":
				target_arch = ""
			case :
				fmt.eprintln("Unsupported target architecture : ", target_arch_str)
				return
			}
		}

		when ODIN_OS == .Windows {
			out_path := strings.join({"-out:", setting["out-path"].(json.String), ".exe"}, "")
		} else {
			out_path := strings.join({"-out:", setting["out-path"].(json.String)}, "")
		}
		defer delete(out_path)
		
		resource :Maybe(string) = nil
		console := false
		if "is-console" in setting {
			console = setting["is-console"].(json.Boolean)
		}
		when ODIN_OS == .Windows {
			if "resource" in setting {
				resource = strings.join({"-resource:",setting["resource"].(json.String)}, "", context.temp_allocator)
			}
		}
		defer if resource != nil do delete(resource.?, context.temp_allocator)

		if !runCmd({"odin", "build", 
		setting["main-package"].(json.String), 
		"-no-bounds-check" if !debug else ({}),
		out_path, 
		o,
		target_arch if target_arch != "" else ({}),
		"-debug" if debug else ({}),
		//"-show-debug-messages",//!for debug
		resource.? if resource != nil else ({}),
		"-define:LOG=true" if log else "-define:LOG=false",
		"-define:CONSOLE=true" if console else "-define:CONSOLE=false",
		("-subsystem:console" if console else "-subsystem:windows") if ODIN_OS == .Windows else ({}),
		//"-sanitize:address" if debug else ({}),
		}) {
			return
		}
	}
}

// findGLSLFileAndRunCmd :: proc() -> bool {
// 	SHADER_DIR :: "core/engine/shaders/"

// 	dir, err := os2.open(filepath.join({ODIN_ROOT, SHADER_DIR}, context.temp_allocator))
// 	if err != nil {
// 		fmt.panicf("findGLSLFiles open ERR : %s", err)
// 	}
// 	defer os2.close(dir)


// 	files, readErr := os2.read_dir(dir, 0, context.allocator)
// 	if readErr != nil {
// 		fmt.panicf("findGLSLFiles read_dir ERR : %s", readErr)
// 	}

// 	defer delete(files)
// 	for file in files {
// 		if file.type != .Regular do continue

// 		ext := filepath.ext(file.name)

// 		glslExts := []string{
// 			".glsl", ".vert", ".frag", ".geom", ".comp", 
// 			".tesc", ".tese", ".rgen", ".rint", ".rahit", 
// 			".rchit", ".rmiss", ".rcall"
// 		}

// 		for vExt in glslExts {
// 			if strings.compare(ext, vExt) == 0 {
// 				spvFile := strings.join({ODIN_ROOT, SHADER_DIR, file.name, ".spv"}, "")
// 				glslFile := strings.join({ODIN_ROOT, SHADER_DIR, file.name}, "")
// 				defer delete(spvFile)
// 				defer delete(glslFile)

// 				if !runCmd({"glslc", glslFile, "-O", "-o", spvFile}) do return false
// 				break
// 			}
// 		}
// 	}

// 	return true
// }

runCmd :: proc(cmd:[]string) -> bool {
	r, w, err := os2.pipe()
	if err != nil do panic("pipe")

	p: os2.Process
	p, err = os2.process_start(os2.Process_Desc{
		command = cmd,
		stdout  = w,
		stderr  = w,
		env = nil,
	})
	os2.close(w)

	output, err2 := os2.read_entire_file_from_file(r, context.temp_allocator)
	//! Unknown Error in Windows, but works fine in Linux
	//if err2 != nil do fmt.panicf("read_entire_file_from_file %s %v", err2, cmd) 

	
	if err != nil {
		fmt.eprint(string(output), err)

		os2.close(r)
		_ = os2.process_close(p)
		return false
		//fmt.panicf("%v", err)
	} else {
		state:os2.Process_State
		state, err = os2.process_wait(p)

		if state.exit_code != 0 {
			fmt.eprint(string(output))

			os2.close(r)
			_ = os2.process_close(p)
			return false
		}

		fmt.print(string(output))
		if err != nil do panic("process_wait")
	}
	_ = os2.process_close(p)

	return true
}