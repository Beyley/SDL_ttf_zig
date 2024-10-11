const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("upstream", .{});

    const sdl_lib_dir = b.option([]const u8, "sdl_lib_dir", "The directory which contains the SDL3 lib to link against");
    const sdl_inc_dir = b.option([]const u8, "sdl_include_dir", "The directory which contains the SDL3 headers to compile against");

    const pic = b.option(bool, "pic", "Whether to force enable/disable Position Independent Code");
    const shared = b.option(bool, "build_shared", "Whether to build SDL_ttf as a shared library") orelse false;

    const harfbuzz = b.option(bool, "use_harfbuzz", "Whether to use Harfbuzz inside of SDL_ttf") orelse true;

    const samples = b.option(bool, "build_samples", "Whether to build the SDL_ttf sample applications") orelse true;

    const disable_pkg_config = b.option(bool, "disable_pkg_config", "Whether to disable pkg-config support when linking libraries") orelse false;

    const options = .{
        .name = "SDL_ttf",
        .optimize = optimize,
        .target = target,
    };

    const sdl_ttf = if (shared) b.addSharedLibrary(options) else b.addStaticLibrary(options);
    sdl_ttf.root_module.sanitize_c = false;

    // TODO: this is probably not the correct way of going about this...
    // https://github.com/libsdl-org/SDL_ttf/blob/45faf5a38bd8f9319ac0fe66cfcc4ceb192f9fa4/CMakeLists.txt#L98
    // Enable large file support on 32-bit glibc
    if (std.mem.startsWith(u8, @tagName(target.result.abi), "gnu") and target.result.ptrBitWidth() == 32) {
        sdl_ttf.root_module.addCMacro("_FILE_OFFSET_BITS", "64");
    }

    sdl_ttf.addCSourceFiles(.{
        .files = &.{
            "SDL_hashtable.c",
            "SDL_renderer_textengine.c",
            "SDL_surface_textengine.c",
            "SDL_ttf.c",
        },
        .root = upstream.path("src/"),
    });
    sdl_ttf.installHeadersDirectory(upstream.path("include/"), "", .{});
    sdl_ttf.addIncludePath(upstream.path("include/"));

    linkSdl(sdl_ttf, sdl_inc_dir, sdl_lib_dir, shared, disable_pkg_config);

    if (shared and target.result.os.tag == .windows) {
        sdl_ttf.addWin32ResourceFile(.{ .file = upstream.path("src/version.rc") });
    }

    sdl_ttf.root_module.addCMacro("DLL_EXPORT", "");

    if (shared or (pic orelse false)) {
        sdl_ttf.root_module.pic = true;
    }

    if (harfbuzz) {
        if (b.lazyDependency("harfbuzz", .{ .target = target, .optimize = optimize })) |harfbuzz_dep| {
            const harfbuzz_lib = harfbuzz_dep.artifact("harfbuzz");
            sdl_ttf.linkLibrary(harfbuzz_lib);
            sdl_ttf.addIncludePath(b.path("src"));
        }

        sdl_ttf.root_module.addCMacro("TTF_USE_HARFBUZZ", "1");
        sdl_ttf.root_module.addCMacro("hb", "harfbuzz/hb");
    }

    if (b.lazyDependency("freetype", .{ .target = target, .optimize = optimize })) |freetype_dep| {
        const freetype_lib = freetype_dep.artifact("freetype");
        sdl_ttf.linkLibrary(freetype_lib);
    }

    b.installArtifact(sdl_ttf);

    if (samples) {
        const glfont = b.addExecutable(.{
            .name = "glfont",
            .optimize = optimize,
            .target = target,
        });

        glfont.root_module.addCMacro("HAVE_OPENGL", "1");
        glfont.linkSystemLibrary2("OpenGL", .{ .use_pkg_config = if (disable_pkg_config) .no else .yes });
        glfont.linkLibrary(sdl_ttf);
        glfont.addCSourceFile(.{ .file = upstream.path("examples/glfont.c") });
        linkSdl(glfont, sdl_inc_dir, sdl_lib_dir, shared, disable_pkg_config);

        b.installArtifact(glfont);

        const showfont = b.addExecutable(.{
            .name = "showfont",
            .optimize = optimize,
            .target = target,
        });

        showfont.linkLibrary(sdl_ttf);
        showfont.addCSourceFiles(.{
            .files = &.{
                "showfont.c",
                "editbox.c",
            },
            .root = upstream.path("examples/"),
        });
        linkSdl(showfont, sdl_inc_dir, sdl_lib_dir, shared, disable_pkg_config);

        b.installArtifact(showfont);

        const testapp = b.addExecutable(.{
            .name = "testapp",
            .optimize = optimize,
            .target = target,
        });

        testapp.linkLibrary(sdl_ttf);
        testapp.addCSourceFile(.{ .file = upstream.path("examples/testapp.c") });
        linkSdl(testapp, sdl_inc_dir, sdl_lib_dir, shared, disable_pkg_config);

        b.installArtifact(testapp);
    }
}

fn linkSdl(
    step: *std.Build.Step.Compile,
    sdl_inc_dir: ?[]const u8,
    sdl_lib_dir: ?[]const u8,
    shared: bool,
    disable_pkg_config: bool,
) void {
    if (sdl_inc_dir) |sdl_inc_dir_path|
        step.addIncludePath(.{ .cwd_relative = sdl_inc_dir_path });
    if (sdl_lib_dir) |sdl_lib_dir_path|
        step.addLibraryPath(.{ .cwd_relative = sdl_lib_dir_path });

    step.linkSystemLibrary2("SDL3", .{
        .preferred_link_mode = if (shared) .dynamic else .static,
        .use_pkg_config = if (disable_pkg_config) .no else .yes,
    });
}
