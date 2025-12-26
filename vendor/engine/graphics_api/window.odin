package graphics_api

import "core:sync"
import "core:math/linalg"

VSync :: enum {Double, Triple, None}

ScreenMode :: enum {Window, Borderless, Fullscreen}

ScreenOrientation :: enum {
	Unknown,
	Landscape90,
	Landscape270,
	Vertical180,
	Vertical360,
}

MonitorInfo :: struct {
	rect:       linalg.RectI,
	refreshRate: u32,
	name:       string,
	isPrimary:  bool,
}

__windowWidth: Maybe(int)
__windowHeight: Maybe(int)
__windowX: Maybe(int)
__windowY: Maybe(int)

prevWindowX: int
prevWindowY: int
prevWindowWidth: int
prevWindowHeight: int

__screenIdx: int = 0
__screenMode: ScreenMode
__windowTitle: cstring
__screenOrientation:ScreenOrientation = .Unknown

monitorsMtx:sync.Mutex
monitors: [dynamic]MonitorInfo
primaryMonitor: ^MonitorInfo
currentMonitor: ^MonitorInfo = nil

__isFullScreenEx := false
__vSync:VSync
monitorLocked:bool = false

paused := false
activated := false
sizeUpdated := false

fullScreenMtx : sync.Mutex

SavePrevWindow :: proc "contextless" () {
	prevWindowX = __windowX.?
    prevWindowY = __windowY.?
    prevWindowWidth = __windowWidth.?
    prevWindowHeight = __windowHeight.?
}
