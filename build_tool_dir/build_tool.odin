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
	log := true
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

	if !findGLSLFileAndRunCmd() do return

	if is_android {
		android_paths := (json_data.(json.Object)["android-paths"]).(json.Object)
		os2.make_directory("android")
		os2.make_directory("android/lib")
		os2.make_directory("android/lib/lib")

		os2.make_directory("android/lib/lib/arm64-v8a")
		err := os2.copy_file("android/lib/lib/arm64-v8a/libVkLayer_khronos_validation.so", filepath.join({ODIN_ROOT, "/vendor/vulkan/lib/android/libVkLayer_khronos_validation_arm64.so"}, context.temp_allocator))
		if err != nil {
			fmt.panicf("libVkLayer_khronos_validation copy_file: %s", err)
		}
		defer os2.remove("android/lib/lib/arm64-v8a/libVkLayer_khronos_validation.so")
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

		ndkPath := android_paths["ndk"].(json.String)
		sdkPath := android_paths["sdk"].(json.String)
		PLATFORM := android_paths["platform-version"].(json.Float)

		builded := false

		os2.set_env("ODIN_ANDROID_SDK", sdkPath)
		os2.set_env("ODIN_ANDROID_NDK", ndkPath)
		when ODIN_OS == .Windows {
			os2.set_env("ODIN_ANDROID_NDK_TOOLCHAIN", strings.join({ndkPath, "/toolchains/llvm/prebuilt/windows-x86_64"}, "", context.temp_allocator))
		} else when ODIN_OS == .Linux {
			os2.set_env("ODIN_ANDROID_NDK_TOOLCHAIN", strings.join({ndkPath, "/toolchains/llvm/prebuilt/linux-x86_64"}, "", context.temp_allocator))
		} else {
			#panic("Unsupported OS for Android build")
		}
		
		for target, i in targets {
			if !runCmd({"odin", "build", 
			setting["main-package"].(json.String), 
			"-no-bounds-check" if !debug else ({}),
			strings.join({"-out:", outSos[i]}, "", context.temp_allocator), 
			o, 
			"-debug" if debug else ({}),
			"-define:__log__=true" if log else ({}),
			//"-show-system-calls" if debug else ({}),
			//"-sanitize:address" if debug else ({}),
			"-build-mode:shared",
			target,
			"-subtarget:android",
			fmt.aprint("-minimum-os-version:", PLATFORM, sep = "", allocator = context.temp_allocator),
			//"-extra-linker-flags:\"-L lib/lib/arm64-v8a -lVkLayer_khronos_validation\"" if debug else ({}),
			}) {
				return
			}

			//?"$ANDROID_JBR/bin/keytool" -genkey -v -keystore .keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000
			if !runCmd({"odin", "bundle", "android", "android", "-android-keystore:android/debug.keystore", "-android-keystore-password:android",
			}) {
				return
			}

			builded = true

			os2.copy_file(strings.join({setting["out-path"].(json.String), ".apk"}, "", context.temp_allocator),
				"test.apk")

			break//!only supports arm64 now
		}

		if builded {
			os2.remove("test.apk")
			os2.remove("test.apk-build")
			os2.remove("test.apk.idsig")
		}	
	} else {
		when ODIN_OS == .Windows {
			out_path := strings.join({"-out:", setting["out-path"].(json.String), ".exe"}, "")
		} else {
			out_path := strings.join({"-out:", setting["out-path"].(json.String)}, "")
		}
		defer delete(out_path)
		
		resource :Maybe(string) = nil
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
		"-debug" if debug else ({}),
		resource.? if resource != nil else ({}),
		"-define:__log__=true" if log else ({}),
		//"-sanitize:address" if debug else ({}),
		}) {
			return
		}
	}
}

findGLSLFileAndRunCmd :: proc() -> bool {
	dir, err := os2.open(filepath.join({ODIN_ROOT, "vendor/engine/shaders"}, context.temp_allocator))
	if err != nil {
		fmt.panicf("findGLSLFiles open ERR : %s", err)
	}
	defer os2.close(dir)


	files, readErr := os2.read_dir(dir, 0, context.allocator)
	if readErr != nil {
		fmt.panicf("findGLSLFiles read_dir ERR : %s", readErr)
	}

	defer delete(files)
	for file in files {
		if file.type != .Regular do continue

		ext := filepath.ext(file.name)

		glslExts := []string{
			".glsl", ".vert", ".frag", ".geom", ".comp", 
			".tesc", ".tese", ".rgen", ".rint", ".rahit", 
			".rchit", ".rmiss", ".rcall"
		}

		for vExt in glslExts {
			if strings.compare(ext, vExt) == 0 {
				spvFile := strings.join({ODIN_ROOT, "vendor/engine/shaders/", file.name, ".spv"}, "")
				glslFile := strings.join({ODIN_ROOT, "vendor/engine/shaders/", file.name}, "")
				defer delete(spvFile)
				defer delete(glslFile)

				if !runCmd({"glslc", glslFile, "-O", "-o", spvFile}) do return false
				break
			}
		}
	}

	return true
}

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