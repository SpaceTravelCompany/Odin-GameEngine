package graphics_api

import "core:math/linalg"


KEY_SIZE :: 512
keys : [KEY_SIZE]bool = { 0..<KEY_SIZE = false }
isMouseOut:bool
mouse_pos:linalg.PointF
scrollDt:int