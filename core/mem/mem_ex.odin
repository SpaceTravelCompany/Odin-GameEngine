package mem

import "base:intrinsics"
import "base:runtime"

make_non_zeroed :: proc {
	make_non_zeroed_slice,
	make_non_zeroed_dynamic_array,
	make_non_zeroed_dynamic_array_len,
	make_non_zeroed_dynamic_array_len_cap,

	//make_non_zeroed_map,
	//make_non_zeroed_map_cap, //?no required
	make_non_zeroed_multi_pointer,

	//TODO
	// make_non_zeroed_soa_slice,
	// make_non_zeroed_soa_dynamic_array,
	// make_non_zeroed_soa_dynamic_array_len,
	// make_non_zeroed_soa_dynamic_array_len_cap,

	make_non_zeroed_aligned_slice,
}

@(require_results)
make_non_zeroed_slice :: proc($T: typeid/[]$E, #any_int len: int, allocator := context.allocator, loc := #caller_location) -> (T, runtime.Allocator_Error) #optional_allocator_error {
	runtime.make_slice_error_loc(loc, len)
	data, err := runtime.mem_alloc_non_zeroed(size_of(E)*len, align_of(E), allocator, loc)
	if data == nil && size_of(E) != 0 {
		return nil, err
	}
	s := runtime.Raw_Slice{raw_data(data), len}

	return transmute(T)s, err
}

@(require_results)
make_non_zeroed_aligned_slice :: proc($T: typeid/[]$E, #any_int len: int, alignment: int, allocator := context.allocator, loc := #caller_location) -> (T, runtime.Allocator_Error) #optional_allocator_error {
	runtime.make_slice_error_loc(loc, len)
	data, err := runtime.mem_alloc_non_zeroed(size_of(E)*len, alignment, allocator, loc)
	if data == nil && size_of(E) != 0 {
		return nil, err
	}
	s := runtime.Raw_Slice{raw_data(data), len}
	return transmute(T)s, err
}

@(require_results)
make_non_zeroed_dynamic_array :: proc($T: typeid/[dynamic]$E, allocator := context.allocator, loc := #caller_location) -> (T, runtime.Allocator_Error) #optional_allocator_error {
	return make_dynamic_array_len_cap(T, 0, 0, allocator, loc)
}

@(require_results)
make_non_zeroed_dynamic_array_len :: proc($T: typeid/[dynamic]$E,  #any_int len: int, allocator := context.allocator, loc := #caller_location) -> (T, runtime.Allocator_Error) #optional_allocator_error {
	return make_dynamic_array_len_cap(T, len, len, allocator, loc)
}

@(require_results)
make_non_zeroed_dynamic_array_len_cap :: proc($T: typeid/[dynamic]$E, #any_int len: int, #any_int cap: int, allocator := context.allocator, loc := #caller_location) -> (array: T, err: runtime.Allocator_Error) #optional_allocator_error {
	runtime.make_dynamic_array_error_loc(loc, 0, 0)

	raw_array := (^runtime.Raw_Dynamic_Array)(&array)

	raw_array.allocator = allocator // initialize allocator before just in case it fails to allocate any memory
	data := runtime.mem_alloc_non_zeroed(size_of(E) * cap, align_of(E), allocator, loc) or_return
	use_zero := data == nil /*&& size_of(E) != 0*/
	raw_array.data = raw_data(data)
	raw_array.len = 0 if use_zero else len
	raw_array.cap = 0 if use_zero else cap
	raw_array.allocator = allocator
	return
}

@(require_results)
make_non_zeroed_multi_pointer :: proc($T: typeid/[^]$E, #any_int len: int, allocator := context.allocator, loc := #caller_location) -> (mp: T, err: runtime.Allocator_Error) #optional_allocator_error {
	runtime.make_slice_error_loc(loc, len)
	data := runtime.mem_alloc_non_zeroed(size_of(E)*len, align_of(E), allocator, loc) or_return
	if data == nil && size_of(E) != 0 {
		return
	}
	mp = cast(T)raw_data(data)
	return
}

@(require_results)
new_non_zeroed :: proc($T: typeid, allocator := context.allocator, loc := #caller_location) -> (^T, runtime.Allocator_Error) #optional_allocator_error {
	return new_non_zeroed_aligned(T, align_of(T), allocator, loc)
}
@(require_results)
new_non_zeroed_aligned :: proc($T: typeid, alignment: int, allocator := context.allocator, loc := #caller_location) -> (t: ^T, err: runtime.Allocator_Error) {
	data := runtime.mem_alloc_non_zeroed(size_of(T), alignment, allocator, loc) or_return
	t = (^T)(raw_data(data))
	return
}

@(require_results)
new_non_zeroed_clone :: proc(data: $T, allocator := context.allocator, loc := #caller_location) -> (t: ^T, err: runtime.Allocator_Error) #optional_allocator_error {
	t_data := runtime.mem_alloc_non_zeroed(size_of(T), align_of(T), allocator, loc) or_return
	t = (^T)(raw_data(t_data))
	if t != nil {
		t^ = data
	}
	return
}

@(require_results)
resize_non_zeroed_slice :: proc(oldData: $T/[]$E, #any_int newLen: int, allocator := context.allocator, loc := #caller_location) -> (T, runtime.Allocator_Error) #optional_allocator_error {
	make_resize_slice_error_loc(loc, len(oldData), newLen)
	if len(oldData) == newLen do return oldData, .None

	data, err := runtime.non_zero_mem_resize(raw_data(oldData), len(oldData) * size_of(E), newLen * size_of(E), align_of(E), allocator)
	if err != .None {
		return nil, err
	}
	s := runtime.Raw_Slice{raw_data(data), newLen}

	return transmute(T)s, err
}

@(require_results)
resize_slice :: proc(oldData: $T/[]$E, #any_int newLen: int, allocator := context.allocator, loc := #caller_location) -> (T, runtime.Allocator_Error) #optional_allocator_error {
	make_resize_slice_error_loc(loc, len(oldData), newLen)
	if len(oldData) == newLen do return oldData, .None
	data, err := runtime.mem_resize(raw_data(oldData), len(oldData) * size_of(E), newLen * size_of(E), align_of(E),  allocator)
	if err != .None {
		return nil, err
	}
	s := runtime.Raw_Slice{raw_data(data), newLen}

	return transmute(T)s, err
}

@(require_results)
resize_non_zeroed_slice_aligned :: proc(oldData: $T/[]$E, #any_int newLen: int, alignment: int, allocator := context.allocator, loc := #caller_location) -> (T, runtime.Allocator_Error) #optional_allocator_error {
	make_resize_slice_error_loc(loc, len(oldData), newLen)
	if len(oldData) == newLen do return oldData, .None

	data, err := runtime.non_zero_mem_resize(raw_data(oldData), len(oldData) * size_of(E), newLen * size_of(E), alignment, allocator)
	if err != .None {
		return nil, err
	}
	s := runtime.Raw_Slice{raw_data(data), newLen}

	return transmute(T)s, err
}

@(require_results)
resize_slice_aligned :: proc(oldData: $T/[]$E, #any_int newLen: int, alignment: int, allocator := context.allocator, loc := #caller_location) -> (T, runtime.Allocator_Error) #optional_allocator_error {
	make_resize_slice_error_loc(loc, len(oldData), newLen)
	if len(oldData) == newLen do return oldData, .None
	data, err := runtime.mem_resize(raw_data(oldData), len(oldData) * size_of(E), newLen * size_of(E), alignment,  allocator)
	if err != .None {
		return nil, err
	}
	s := runtime.Raw_Slice{raw_data(data), newLen}

	return transmute(T)s, err
}


@(disabled=ODIN_NO_BOUNDS_CHECK)
make_resize_slice_error_loc :: #force_inline proc "contextless" (loc := #caller_location, #any_int oldLen: int, #any_int newLen: int) {
	if 0 <= oldLen && 0 <= newLen {
		return
	}
	@(cold, no_instrumentation)
	handle_error :: proc "contextless" (loc: runtime.Source_Code_Location, oldLen, newLen: int) -> ! {
		runtime.print_caller_location(loc)
		runtime.print_string(" Invalid slice length for make: ")
		runtime.print_i64(i64(oldLen))
		runtime.print_string(", ")
		runtime.print_i64(i64(newLen))
		runtime.print_byte('\n')
		runtime.bounds_trap()
	}
	handle_error(loc, oldLen, newLen)
}