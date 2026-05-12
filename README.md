# zsh-log-copy

`zsh-log-copy` captures the output of the last log-oriented command in the current interactive zsh session. Run `copylast` to copy that output to your clipboard.

## Install

One-line install:

```zsh
curl -fsSL https://raw.githubusercontent.com/0601p/zsh-log-copy/main/install.sh | sh
```

The installer clones this repository to `~/.zsh-log-copy` and adds this plugin to your `.zshrc`. Restart your shell after installing, or run `source ~/.zshrc`.

Source the plugin from your `.zshrc`:

```zsh
source /path/to/zsh-log-copy/zsh-log-copy.plugin.zsh
```

With a plugin manager, load this repository as a zsh plugin. The plugin entrypoint is:

```text
zsh-log-copy.plugin.zsh
```

## Usage

```zsh
python train.py
cpl
```

Commands:

```zsh
cpl               # copy the last captured output to the clipboard
cpl --print       # print the last captured output
cpl --path        # print the current session log path
cpl --help        # show usage
copylast          # same as cpl
```

Temporarily disable or re-enable capture:

```zsh
zsh-log-copy-disable
zsh-log-copy-enable
```

## Configuration

By default, logs are stored under:

```zsh
${TMPDIR:-/tmp}/zsh-log-copy
```

Override the base directory before loading the plugin:

```zsh
ZSH_LOG_COPY_BASE_DIR="$HOME/.cache/zsh-log-copy"
source /path/to/zsh-log-copy/zsh-log-copy.plugin.zsh
```

Each zsh session gets its own `last.log`, and every captured command replaces the previous log for that session. Commands that are not captured leave the previous captured log intact.

By default, the plugin captures common program-log commands:

```text
sh, bash, zsh, dash, ksh
python, python2, python3, pypy, pypy3
ruby, perl, php, lua, R/Rscript, julia
node, deno, bun, ts-node, npx
pytest, py.test, tox, nox
npm, pnpm, yarn
make, cmake, ctest, ninja, meson, bazel, scons, xcodebuild
C/C++ compilers: cc, gcc, g++, clang, clang++, nvcc, hipcc
Fortran compilers and MPI wrappers: gfortran, ifort, flang, mpicc, mpicxx, mpirun, mpiexec
cargo, rustc, go, java, javac, mvn, gradle, gradlew
scala, sbt, kotlin, kotlinc, dotnet, swift, dart, flutter
elixir, mix, erlc, rebar3, dune, ocaml, cabal, stack, ghc
pip, pip2, pip3, pipx, poetry, uv, conda
sr, srun
local executables such as ./a.out, ./main, build/train, or /path/to/program
```

Shell and interpreter commands are captured only when they look like they are running a script or command. For example, `python train.py`, `python -m pytest`, `ruby test.rb`, `node app.js`, `sh run.sh`, and `bash -lc 'make test'` are captured, but bare `python`, bare `ruby`, and bare `bash` are not.

To add commands before loading the plugin:

```zsh
ZSH_LOG_COPY_CAPTURE_COMMANDS+=(my-runner my-test-command)
source /path/to/zsh-log-copy/zsh-log-copy.plugin.zsh
```

To capture every command:

```zsh
ZSH_LOG_COPY_CAPTURE_ALL=1
source /path/to/zsh-log-copy/zsh-log-copy.plugin.zsh
```

## Clipboard Support

`copylast` tries these clipboard commands in order:

```text
pbcopy, wl-copy, xclip, xsel, clip.exe, OSC 52
```

OSC 52 is the fallback for SSH sessions where the remote server has no local clipboard command. It asks your local terminal to copy the text. Your terminal must allow OSC 52 clipboard access; tmux may also need passthrough enabled.

## Notes

The plugin captures both stdout and stderr. `copylast`/`cpl` strips terminal escape sequences from copied or printed output, including shell integration markers such as VS Code/Cursor OSC 633. It uses zsh `preexec` and `precmd` hooks plus `tee`, so commands that check whether stdout or stderr is a real TTY may format output differently while they are being captured. stdout and stderr are captured through separate streams, so their relative order in `last.log` can differ for commands that write to both at nearly the same time.
