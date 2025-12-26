#+build !freestanding
//#+build !js // edited (xfitgd)
package fmt

import "base:runtime"
import "core:os"
import "core:io"
import "core:bufio"
import "base:library"

// fprint formats using the default print settings and writes to fd
fprint :: proc(fd: os.Handle, args: ..any, sep := " ", flush := true) -> int {
	buf: [1024]byte
	b: bufio.Writer
	defer bufio.writer_flush(&b)

	bufio.writer_init_with_buf(&b, os.stream_from_handle(fd), buf[:])
	w := bufio.writer_to_writer(&b)
	return wprint(w, ..args, sep=sep, flush=flush)
}

// fprintln formats using the default print settings and writes to fd
fprintln :: proc(fd: os.Handle, args: ..any, sep := " ", flush := true) -> int {
	buf: [1024]byte
	b: bufio.Writer
	defer bufio.writer_flush(&b)

	bufio.writer_init_with_buf(&b, os.stream_from_handle(fd), buf[:])

	w := bufio.writer_to_writer(&b)
	return wprintln(w, ..args, sep=sep, flush=flush)
}
// fprintf formats according to the specified format string and writes to fd
fprintf :: proc(fd: os.Handle, fmt: string, args: ..any, flush := true, newline := false) -> int {
	buf: [1024]byte
	b: bufio.Writer
	defer bufio.writer_flush(&b)

	bufio.writer_init_with_buf(&b, os.stream_from_handle(fd), buf[:])

	w := bufio.writer_to_writer(&b)
	return wprintf(w, fmt, ..args, flush=flush, newline=newline)
}
// fprintfln formats according to the specified format string and writes to fd, followed by a newline.
fprintfln :: proc(fd: os.Handle, fmt: string, args: ..any, flush := true) -> int {
	return fprintf(fd, fmt, ..args, flush=flush, newline=true)
}
fprint_type :: proc(fd: os.Handle, info: ^runtime.Type_Info, flush := true) -> (n: int, err: io.Error) {
	buf: [1024]byte
	b: bufio.Writer
	defer bufio.writer_flush(&b)

	bufio.writer_init_with_buf(&b, os.stream_from_handle(fd), buf[:])

	w := bufio.writer_to_writer(&b)
	return wprint_type(w, info, flush=flush)
}
fprint_typeid :: proc(fd: os.Handle, id: typeid, flush := true) -> (n: int, err: io.Error) {
	buf: [1024]byte
	b: bufio.Writer
	defer bufio.writer_flush(&b)

	bufio.writer_init_with_buf(&b, os.stream_from_handle(fd), buf[:])

	w := bufio.writer_to_writer(&b)
	return wprint_typeid(w, id, flush=flush)
}

// edited (xfitgd)
// print formats using the default print settings and writes to os.stdout
__print    :: proc(args: ..any, sep := " ", flush := true) -> int { return fprint(os.stdout, ..args, sep=sep, flush=flush) }
// println formats using the default print settings and writes to os.stdout
__println  :: proc(args: ..any, sep := " ", flush := true) -> int { return fprintln(os.stdout, ..args, sep=sep, flush=flush) }
// printf formats according to the specified format string and writes to os.stdout
__printf   :: proc(fmt: string, args: ..any, flush := true) -> int { return fprintf(os.stdout, fmt, ..args, flush=flush) }
// printfln formats according to the specified format string and writes to os.stdout, followed by a newline.
__printfln :: proc(fmt: string, args: ..any, flush := true) -> int { return fprintf(os.stdout, fmt, ..args, flush=flush, newline=true) }

// eprint formats using the default print settings and writes to os.stderr
eprint    :: proc(args: ..any, sep := " ", flush := true) -> int { return fprint(os.stderr, ..args, sep=sep, flush=flush) }
// eprintln formats using the default print settings and writes to os.stderr
eprintln  :: proc(args: ..any, sep := " ", flush := true) -> int { return fprintln(os.stderr, ..args, sep=sep, flush=flush) }
// eprintf formats according to the specified format string and writes to os.stderr
eprintf   :: proc(fmt: string, args: ..any, flush := true) -> int { return fprintf(os.stderr, fmt, ..args, flush=flush) }
// eprintfln formats according to the specified format string and writes to os.stderr, followed by a newline.
eprintfln :: proc(fmt: string, args: ..any, flush := true) -> int { return fprintf(os.stderr, fmt, ..args, flush=flush, newline=true) }

// edited (xfitgd)
when library.is_android {
	print :: proc(args: ..any, sep := " ", flush := true) -> int {
		_ = flush
		cstr := fmt.caprint(..args, sep=sep)
		defer delete(cstr)
		return auto_cast android.__android_log_write(android.LogPriority.INFO, ODIN_BUILD_PROJECT_NAME, cstr)
	}
	println  :: print
	printf   :: proc(_fmt: string, args: ..any, flush := true) -> int {
		_ = flush
		cstr := fmt.caprintf(_fmt, ..args)
		defer delete(cstr)
		return auto_cast android.__android_log_write(android.LogPriority.INFO, ODIN_BUILD_PROJECT_NAME, cstr)
	}
	printfln :: printf
	printCustomAndroid :: proc(args: ..any, logPriority: android.LogPriority = .INFO, sep := " ") -> int {
		cstr := fmt.caprint(..args, sep=sep)
		defer delete(cstr)
		return auto_cast android.__android_log_write(logPriority, ODIN_BUILD_PROJECT_NAME, cstr)
	}
} else {
	println :: __println
	printfln :: __printfln
	printf :: __printf
	print :: __print

	/**
	* Android log priority values, in increasing order of priority.
	*/
	LogPriority :: enum i32 {
	/** For internal use only.  */
	UNKNOWN = 0,
	/** The default priority, for internal use only.  */
	DEFAULT, /* only for SetMinPriority() */
	/** Verbose logging. Should typically be disabled for a release apk. */
	VERBOSE,
	/** Debug logging. Should typically be disabled for a release apk. */
	DEBUG,
	/** Informational logging. Should typically be disabled for a release apk. */
	INFO,
	/** Warning logging. For use with recoverable failures. */
	WARN,
	/** Error logging. For use with unrecoverable failures. */
	ERROR,
	/** Fatal logging. For use when aborting. */
	FATAL,
	/** For internal use only.  */
	SILENT, /* only for SetMinPriority(); must be last */
	}

	printCustomAndroid :: proc(args: ..any, logPriority:LogPriority = .INFO, sep := " ") -> int {
		_ = logPriority
		return print(..args, sep = sep)
	}
}