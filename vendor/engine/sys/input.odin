package sys

import "core:math/linalg"


key_size :: 512
keys : [key_size]bool = { 0..<key_size = false }
is_mouse_out:bool
mouse_pos:linalg.PointF
scroll_dt:int