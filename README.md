# zegg

deferred-rebuilding e-graph in zig

## Purpose

EGG is a popular library in Rust, and I think Zig's comptime will make it easier to use than proc macros, and it should be possible to have more efficient allocation strategies.

## Installation

Zig has a package manager. Something like the following ought to work.

```zig
// build.zig.zon
.{
    .name = "foo",
    .version = "0.0.0",
    .dependencies = .{
        .zunion = .{
            .url = "https://github.com/hmusgrave/zegg/archive/ba5568f7b3615c636ab987bf71f0eab9fa266e73.tar.gz",
        },
    },

}
```

```zig
// build.zig
const zegg_pkg = b.dependency("zegg", .{
    .target = target,
    .optimize = optimize,
});
const zegg_mod = zegg_pkg.module("zegg");
lib.addModule("zegg", zegg_mod);
main_tests.addModule("zegg", zegg_mod);
```

## Status

I'm building this targeting 0.12.0-dev.86+197d9a9eb right now. It compiles. The e-graph works. It doesn't have many efficiencies applied beyond what the Rust version would have. I haven't finished working through the whitepaper it's based on (e-class analyses, ematch, ...).
