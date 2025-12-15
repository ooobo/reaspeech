# Development

We expect that roughly 96.7533% of users will have their needs met with things
as they are, but for that remaining 3.2467% here's how you can make changes
and rebuild.

## Design Philosophy

Programming with Lua inside of REAPER - while generally fluid and intuitive,
once you understand the model that ReaScript provides - can be tricky and
littered with gotchas that can (and have) left even the most seasoned
developers in a somewhat-comatose state of crisis, only emitting a faint but
discernible existential wail.

ReaSpeech code is written to mostly respect the top-level namespace and
environment of the running Lua interpreter. Use of globals is limited to the
variables `app` (the single instance of `ReaSpeechUI`) and `ctx` (the ImGui
context) - both instantiated in `ReaSpeechMain.lua`.

"Building" the script for distribution consists of concatenating a specified
collection of Lua source files (everything in `source` and from a common
library), so any code should be written to not assume that any symbols or
objects (variables, tables or "classes") are available on the initial parse
(see `source/libs/IntervalFunction.lua` for an example of how ReaScript-aware
code is written but deferred). By doing things this way, we avoid confusion
as to the loading behavior of Lua modules within REAPER, at the expense of
defining these symbols up-front and independently of any other code.

Having said all this, there are a few guarantees of bundle order. The main
directories under `source` (`libs`, `ui` & `main`) represent their own stages.
This means that you can count on symbols from previous stages being bundled
(and therefore present in the namespace) by the time later stages are
processed. If you want to confidently use in top-level code any symbols
within the same stage, it might be best to do the deferred loading described
above.

Further, directories that exist lower in a hierarchy will be bundled after
any sibling `*.lua` files. An example here is `source/ui/widgets/*.lua` which
will appear in the bundle after everything in `source/ui/*.lua`.

## Building ReaScripts

The ReaSpeech UI and related code are in a set of Lua files in the "reascripts"
directory. If you have the necessary dependencies (see the Makefile for details),
you can build the ReaScripts by running:

```sh
cd reascripts/ReaSpeech
make
```

### Automatic Rebuilding

If you would like the ReaScripts to be automatically rebuilt whenever you make
changes to the Lua files, you can run the following command:

```sh
# CPU version
scripts/reawatch ReaSpeech
```

### Build-Free ReaScript Development

A "ReaSpeechDev.lua" file is provided in the "reascripts/ReaSpeech" directory.
This file loads all of the Lua source files directly each time it runs,
enabling you to make changes to the Lua files and see the changes reflected in
REAPER without having to rebuild the ReaScripts. To use this file, add it as
an action in REAPER.

### Building transcription executables

Requires rust compiler. Navigate to "rust-parakeet".
**Windows:** cargo build --release --bin parakeet-transcribe-windows
**Mac:** cargo build --release --bin parakeet-transcribe-macos
These executables must be in same folder as ReaSpeech.lua script.

### To push a release

1. Add commits to beta branch
2. `git tag v0.7.1-fork##`
3. `git push origin v0.7.1-fork##`

GitHub Actions will create the release, update index.xml for ReaPack repository at (https://github.com/ooobo/reaspeech/raw/beta/index.xml) to pick up.
