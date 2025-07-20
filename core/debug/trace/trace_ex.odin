package debug_trace

import "core:strings"
import "core:os"
import "core:fmt"
import "core:sync"
import "base:runtime"
import "base:intrinsics"
import "core:sys/android"

@(private = "file") is_android :: ODIN_PLATFORM_SUBTARGET == .Android
@(private = "file") is_mobile :: is_android

LOG_FILE_NAME: string = "odin_log.log"

@(init, private) init_trace :: proc() {
	when !is_android {
		sync.mutex_lock(&gTraceMtx)
		defer sync.mutex_unlock(&gTraceMtx)
		init(&gTraceCtx)
	}
}

@(fini, private) deinit_trace :: proc() {
	when !is_android {
		sync.mutex_lock(&gTraceMtx)
		defer sync.mutex_unlock(&gTraceMtx)
		destroy(&gTraceCtx)
	}
}

@(private = "file") gTraceCtx: Context
@(private = "file") gTraceMtx: sync.Mutex

printTrace :: proc() {
	when !is_android {
		sync.mutex_lock(&gTraceMtx)
		defer sync.mutex_unlock(&gTraceMtx)
		if !in_resolve(&gTraceCtx) {
			buf: [64]Frame
			frames := frames(&gTraceCtx, 1, buf[:])
			for f, i in frames {
				fl := resolve(&gTraceCtx, f, context.allocator)
				if fl.loc.file_path == "" && fl.loc.line == 0 do continue
				fmt.printf("%s\n%s called by %s - frame %d\n",
					fl.loc, fl.procedure, fl.loc.procedure, i)
			}
		}
		fmt.printf("-------------------------------------------------\n")
	}
}
printTraceBuf :: proc(str:^strings.Builder) {
	when !is_android {
		sync.mutex_lock(&gTraceMtx)
		defer sync.mutex_unlock(&gTraceMtx)
		if !in_resolve(&gTraceCtx) {
			buf: [64]Frame
			frames := frames(&gTraceCtx, 1, buf[:])
			for f, i in frames {
				fl := resolve(&gTraceCtx, f, context.allocator)
				if fl.loc.file_path == "" && fl.loc.line == 0 do continue
				fmt.sbprintf(str,"%s\n%s called by %s - frame %d\n",
					fl.loc, fl.procedure, fl.loc.procedure, i)
			}
		}
		fmt.sbprintln(str, "-------------------------------------------------\n")
	}
}

@(cold) panic_log :: proc "contextless" (args: ..any, loc := #caller_location) -> ! {
	context = runtime.default_context()
	when !is_android {
		str: strings.Builder
		strings.builder_init(&str)
		fmt.sbprintln(&str,..args)
		fmt.sbprintf(&str,"%s\n%s called by %s\n",
			loc,
			#procedure,
			loc.procedure)

		printTraceBuf(&str)

		printToFile(str.buf[:len(str.buf)])
		panic(string(str.buf[:len(str.buf)]), loc)
	} else {
		cstr := fmt.caprint(..args)
		android.__android_log_write(android.LogPriority.ERROR, ODIN_BUILD_PROJECT_NAME, cstr)

		printToFile((transmute([^]byte)cstr)[:len(cstr)])

		intrinsics.trap()
	}
}

@private printToFile :: proc(str:[]byte) {
	str2 := string(str)
	when !is_android {
		if len(LOG_FILE_NAME) > 0 {
			fd, err := os.open(LOG_FILE_NAME, os.O_WRONLY | os.O_CREATE | os.O_APPEND, 0o644)
			if err == nil {
				defer os.close(fd)
				fmt.fprint(fd, str2)
			}
		}
	} else {
		//TODO (xfitgd)
	}
	fmt.print(str2)
}

printLog :: proc "contextless" (args: ..any) {
	context = runtime.default_context()
	str: strings.Builder
	strings.builder_init(&str)
	defer strings.builder_destroy(&str)
	fmt.sbprint(&str, ..args)

	printToFile(str.buf[:len(str.buf)])
}


printlnLog :: proc "contextless" (args: ..any) {
	context = runtime.default_context()
	str: strings.Builder
	strings.builder_init(&str)
	defer strings.builder_destroy(&str)
	fmt.sbprintln(&str, ..args)

	printToFile(str.buf[:len(str.buf)])
}

printfLog :: proc "contextless" (_fmt:string ,args: ..any) {
	context = runtime.default_context()
	str: strings.Builder
	strings.builder_init(&str)
	defer strings.builder_destroy(&str)
	fmt.sbprintf(&str, _fmt, ..args)

	printToFile(str.buf[:len(str.buf)])
}

printflnLog :: proc "contextless" (_fmt:string ,args: ..any) {
	context = runtime.default_context()
	str: strings.Builder
	strings.builder_init(&str)
	defer strings.builder_destroy(&str)
	fmt.sbprintfln(&str, _fmt, ..args)

	printToFile(str.buf[:len(str.buf)])
}
