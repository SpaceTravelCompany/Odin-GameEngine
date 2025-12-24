package library

is_android :: ODIN_PLATFORM_SUBTARGET == .Android
is_mobile :: is_android

when ODIN_ARCH == .amd64 {
    ARCH_end :: "_amd64.a"
} else when ODIN_ARCH == .i386 {
    ARCH_end :: "_i386.a"
} else when ODIN_ARCH == .arm64 {
    ARCH_end :: "_arm64.a"
} else when ODIN_ARCH == .riscv64 {
    ARCH_end :: "_riscv64.a"
} else when ODIN_ARCH == .arm32 {
    ARCH_end :: "_arm32.a"
}

when !is_mobile {
	when ODIN_OS == .Windows {
		LIBPATH :: "/lib/windows"
	} else when ODIN_OS == .Darwin {
		//TODO
	} else {
		LIBPATH :: "/lib/linux"
    }
} else {
	when is_android {
        LIBPATH :: "/lib/android"
	}
}