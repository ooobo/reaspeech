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

### Build-Free ReaScript Development

A "ReaSpeechDev.lua" file is provided in the "reascripts/ReaSpeech" directory.
This file loads all of the Lua source files directly each time it runs,
enabling you to make changes to the Lua files and see the changes reflected in
REAPER without having to rebuild the ReaScripts. To use this file, add it as
an action in REAPER.

# Fork

Why an executable? I wanted to use NVIDIA's Parakeet TDT model, Docker or a 
web server isn't an option in a lot of studio/editing environments and felt a 
bit insane trying to run it through python. Offloading the complexity to a 
executable that Reaper can just call prevents a lot of mucking around, and I
already had such an executable from another project. Most of the changes to
the original repo were made with Claude in a small amount of time, so can't 
vouch for it's realiability. 

Most of the lua code is from the original (the bones are the hard part), 
just with some UI changes and added functionality.

## Transcription executable

The Rust transcription executable is maintained in a separate repository:
[ooobo/parakeet-transcribe](https://github.com/ooobo/parakeet-transcribe)

To build locally, clone that repo and run:
- **Windows:** `cargo build --release --bin parakeet-transcribe`
- **macOS:** `cargo build --release --bin parakeet-transcribe-macos`

The compiled binary must be placed in the same folder as `ReaSpeech.lua`.

For releases, pre-built binaries are automatically downloaded from
`ooobo/parakeet-transcribe` by the GitHub Actions workflow.

## Creating a release

Releases are built by GitHub Actions and published to the
[ReaPack repository](https://github.com/ooobo/reaspeech/raw/beta/index.xml).

**Steps:**

1. Make sure all changes are committed and pushed to the `beta` branch.
2. Ensure `ooobo/parakeet-transcribe` has a GitHub Release with current
   Windows (`.exe`) and macOS binaries. The release workflow downloads the
   latest binaries from that repo automatically.
3. Choose a version tag, incrementing the number from the last release:
   ```sh
   git tag v0.7.1-fork9
   ```
4. Push the tag to trigger the release workflow:
   ```sh
   git push origin v0.7.1-fork9
   ```
5. GitHub Actions will:
   - Bundle all Lua source files into `ReaSpeech.lua`
   - Download `parakeet-transcribe.exe` and `parakeet-transcribe-macos`
     from `ooobo/parakeet-transcribe`
   - Create a GitHub Release with the bundled script and binaries
   - Update `index.xml` and push it to the `beta` branch
6. ReaPack users receive the update via **Extensions > ReaPack > Synchronize packages**.

**Alternative:** You can also trigger a release manually from the GitHub
Actions tab using "Run workflow" and providing a version tag (e.g. `v0.7.1-fork9`).
