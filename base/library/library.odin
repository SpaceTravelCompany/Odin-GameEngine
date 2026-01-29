package library

is_android :: ODIN_PLATFORM_SUBTARGET == .Android
is_mobile :: is_android

when ODIN_ARCH == .amd64 {
    __ARCH_end :: "_amd64"
} else when ODIN_ARCH == .i386 {
    __ARCH_end :: "_i386"
} else when ODIN_ARCH == .arm64 {
    __ARCH_end :: "_arm64"
} else when ODIN_ARCH == .riscv64 {
    __ARCH_end :: "_riscv64"
} else when ODIN_ARCH == .arm32 {
    __ARCH_end :: "_arm32"
}

when ODIN_OS == .Windows && !is_mobile {
	ARCH_end :: __ARCH_end + ".lib"
	ARCH_end_so :: __ARCH_end + ".dll"
} else {
	ARCH_end :: __ARCH_end + ".a"
	ARCH_end_so :: __ARCH_end + ".so"
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