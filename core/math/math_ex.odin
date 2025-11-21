package math

import "base:intrinsics"

ceil_up :: proc "contextless"(num:$T, multiple:T) -> T where intrinsics.type_is_integer(T) {
	if multiple == 0 do return num

	remain := abs(num) % multiple
	if remain == 0 do return num

	if num < 0 do return -(abs(num) + multiple - remain)
	return num + multiple - remain
}

floor_up :: proc "contextless"(num:$T, multiple:T) -> T where intrinsics.type_is_integer(T) {
	if multiple == 0 do return num

	remain := abs(num) % multiple
	if remain == 0 do return num

	if num < 0 do return -(abs(num) - remain)
	return num - remain
}


//! 현재 매개변수에 배열 이외의 값 (숫자) 을 넣어도 작동되는 버그 있음.
min_array :: proc "contextless" (value0:$T/[$N]$E, values:..T) -> (result:[N]E) {
	for i := 0;i < N;i += 1 {
		m : E = value0[i]
		for v in values {
			if m > v[i] do m = v[i]
		}
		result[i] = m
	}
	return
}

max_array :: proc "contextless" (value0:$T/[$N]$E, values:..T) -> (result:[N]E) {
	for i in 0..<int(N) {
		m : E = value0[i]
		for v in values {
			if m < v[i] do m = v[i]
		}
		result[i] = m
	}
	return
}


splat_2 :: proc "contextless" (scalar:$T) -> [2]T where intrinsics.type_is_numeric(T) {
	return { 0..<2 = scalar }
}
splat_3 :: proc "contextless" (scalar:$T) -> [3]T where intrinsics.type_is_numeric(T) {
	return { 0..<3 = scalar }
}
splat_4 :: proc "contextless" (scalar:$T) -> [4]T where intrinsics.type_is_numeric(T) {
	return { 0..<4 = scalar }
}

epsilon :: proc "contextless" ($T:typeid) -> T where intrinsics.type_is_float(T) {
	if T == f16 || T == f16be || T == f16le do return T(F16_EPSILON)
	if T == f32 || T == f32be || T == f32le do return T(F32_EPSILON)
	return T(F64_EPSILON)
}

epsilon_equal :: proc "contextless" (a:$T, b:T) -> bool where intrinsics.type_is_float(T) {
	return abs(a - b) < epsilon(T)
}

