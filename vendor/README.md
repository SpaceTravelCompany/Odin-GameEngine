# Vendor Collection

The `vendor:` prefix for Odin imports is a package collection that comes with this implementation of the Odin programming language.

Its use is similar to that of `core:` packages, which would be available in any Odin implementation.

Presently, the `vendor:` collection comprises the following packages:

## CommonMark

[CMark](https://github.com/commonmark/cmark) CommonMark parsing library.

See also LICENSE in the `commonmark` directory itself.
Includes full bindings and Windows `.lib` and `.dll`.

## GLFW

Bindings for the multi-platform library for OpenGL, OpenGL ES, Vulkan, window and input API [GLFW](https://github.com/glfw/glfw).

`GLFW.dll` and `GLFW.lib` are available under GLFW's [zlib/libpng](https://www.glfw.org/license.html) license.

See also LICENSE.txt in the `glfw` directory itself.

## lua

[lua](https://www.lua.org) provides bindings and Windows and Linux libraries for Lua versions 5.1 through 5.4.

See also LICENSE in the `lua` directory itself.

## miniaudio

[miniaudio](https://miniaud.io) is a cross-platform An audio playback and capture library.

Miniaudio is open source with a permissive license of your choice of public domain or [MIT No Attribution](https://github.com/aws/mit-0).

## OpenEXRCore

[OpenEXRCore](https://github.com/AcademySoftwareFoundation/openexr) provides the specification and reference implementation of the EXR file format, the professional-grade image storage format of the motion picture industry.

See also LICENSE.md in the `OpenEXRCore` directory itself.

## OpenGL

Bindings for the OpenGL graphics API and helpers in idiomatic Odin to, for example, reload shaders when they're changed on disk.

This package is available under the MIT license. See `LICENSE` and `LICENSE_glad` for more details.

## Vulkan

The Vulkan 3D graphics API are automatically generated from headers provided by Khronos, and are made available under the [Apache License, Version 2.0](https://github.com/KhronosGroup/Vulkan-Headers/blob/master/LICENSE.txt).
