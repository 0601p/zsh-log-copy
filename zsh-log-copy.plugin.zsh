# zsh-log-copy
#
# Capture the output of the last log-oriented command in this zsh session.
# Run `copylast` to copy that captured output to the system clipboard.

[[ -o interactive ]] || return 0

autoload -Uz add-zsh-hook

if [[ -n ${__ZSH_LOG_COPY_LOADED:-} ]]; then
  add-zsh-hook -d preexec __zlc_preexec 2>/dev/null
  add-zsh-hook -d precmd __zlc_precmd 2>/dev/null
  precmd_functions=(${precmd_functions:#__zlc_precmd})
fi
typeset -g __ZSH_LOG_COPY_LOADED=1

: ${ZSH_LOG_COPY_BASE_DIR:=${TMPDIR:-/tmp}/zsh-log-copy}

typeset -g ZSH_LOG_COPY_SESSION_ID="${ZSH_LOG_COPY_SESSION_ID:-${HOST:-host}.$$}"
typeset -g ZSH_LOG_COPY_SESSION_DIR="${ZSH_LOG_COPY_SESSION_DIR:-${ZSH_LOG_COPY_BASE_DIR}/${ZSH_LOG_COPY_SESSION_ID}}"
typeset -g ZSH_LOG_COPY_LAST_LOG="${ZSH_LOG_COPY_LAST_LOG:-${ZSH_LOG_COPY_SESSION_DIR}/last.log}"
typeset -g ZSH_LOG_COPY_SANITIZED_LOG="${ZSH_LOG_COPY_SANITIZED_LOG:-${ZSH_LOG_COPY_SESSION_DIR}/last.sanitized.log}"
typeset -g ZSH_LOG_COPY_LAST_COMMAND="${ZSH_LOG_COPY_LAST_COMMAND:-}"
typeset -g ZSH_LOG_COPY_LAST_STATUS="${ZSH_LOG_COPY_LAST_STATUS:-}"

if (( ! ${+ZSH_LOG_COPY_CAPTURE_COMMANDS} )); then
  typeset -ga ZSH_LOG_COPY_CAPTURE_COMMANDS=(
    sh bash zsh dash ksh
    python python2 python3 pypy pypy3
    node deno bun ts-node npx
    ruby perl php lua luajit R Rscript julia
    pytest py.test tox nox
    npm pnpm yarn
    make cmake ctest ninja meson bazel bazelisk buck buck2 scons xcodebuild
    cc c99 c11 c17 c89 gcc g++ clang clang++ c++ cpp
    icc icpc icx icpx nvcc hipcc
    gfortran ifort ifx flang f77 f95 ftn
    mpicc mpicxx mpic++ mpiCC mpifort mpif77 mpif90 mpirun mpiexec
    cargo rustc go java javac mvn gradle gradlew
    scala scalac sbt kotlin kotlinc
    dotnet csc fsharpc
    swift swiftc dart flutter
    elixir mix erlc rebar3
    dune ocaml ocamlc ocamlopt opam
    cabal stack runghc ghc
    racket raco guile sbcl clisp
    pip pip2 pip3 pipx poetry uv conda
    sr srun
  )
else
  typeset -ga ZSH_LOG_COPY_CAPTURE_COMMANDS
fi

typeset -gi __zlc_active=0
typeset -gi __zlc_stdout_fd=-1
typeset -gi __zlc_stderr_fd=-1
typeset -g __zlc_current_log=""
typeset -g __zlc_stdout_fifo=""
typeset -g __zlc_stderr_fifo=""
typeset -g __zlc_stdout_done=""
typeset -g __zlc_stderr_done=""
typeset -ga __zlc_command_words=()

__zlc_is_assignment_word() {
  emulate -L zsh

  [[ "$1" =~ '^[A-Za-z_][A-Za-z0-9_]*(\+)?=' ]]
}

__zlc_resolve_command_words() {
  emulate -L zsh

  __zlc_command_words=()

  local -a words
  words=("${(z)1}") 2>/dev/null || return 1

  local i=1
  local word

  while (( i <= $#words )); do
    word="${words[i]}"

    if __zlc_is_assignment_word "$word"; then
      (( i++ ))
      continue
    fi

    case "$word" in
      builtin|exec|noglob|nocorrect|time|coproc)
        (( i++ ))
        continue
        ;;
      command)
        (( i++ ))
        while (( i <= $#words )); do
          case "${words[i]}" in
            --)
              (( i++ ))
              break
              ;;
            -p)
              (( i++ ))
              ;;
            -v|-V)
              __zlc_command_words=(command)
              return 0
              ;;
            *)
              break
              ;;
          esac
        done
        continue
        ;;
      sudo)
        (( i++ ))
        while (( i <= $#words )); do
          word="${words[i]}"
          case "$word" in
            --)
              (( i++ ))
              break
              ;;
            -e|--edit)
              __zlc_command_words=(sudoedit)
              return 0
              ;;
            -C|-g|-h|-p|-T|-t|-U|-u|--close-from|--group|--host|--prompt|--chdir|--login-class|--role|--type|--user)
              (( i += 2 ))
              ;;
            -C*|-g*|-h*|-p*|-T*|-t*|-U*|-u*|--close-from=*|--group=*|--host=*|--prompt=*|--chdir=*|--login-class=*|--role=*|--type=*|--user=*)
              (( i++ ))
              ;;
            -*)
              (( i++ ))
              ;;
            *)
              __zlc_is_assignment_word "$word" && { (( i++ )); continue; }
              break
              ;;
          esac
        done
        continue
        ;;
      doas)
        (( i++ ))
        while (( i <= $#words )); do
          word="${words[i]}"
          case "$word" in
            --)
              (( i++ ))
              break
              ;;
            -s)
              __zlc_command_words=(doas-shell)
              return 0
              ;;
            -C|-u)
              (( i += 2 ))
              ;;
            -C*|-u*|-n)
              (( i++ ))
              ;;
            -*)
              (( i++ ))
              ;;
            *)
              __zlc_is_assignment_word "$word" && { (( i++ )); continue; }
              break
              ;;
          esac
        done
        continue
        ;;
      env)
        (( i++ ))
        while (( i <= $#words )); do
          word="${words[i]}"
          case "$word" in
            --)
              (( i++ ))
              break
              ;;
            -u|-C|--unset|--chdir)
              (( i += 2 ))
              ;;
            -S|--split-string)
              __zlc_command_words=(env)
              return 0
              ;;
            -*|--*=*)
              (( i++ ))
              ;;
            *)
              __zlc_is_assignment_word "$word" && { (( i++ )); continue; }
              break
              ;;
          esac
        done
        if (( i > $#words )); then
          __zlc_command_words=(env)
          return 0
        fi
        continue
        ;;
      arch)
        (( i++ ))
        while (( i <= $#words && "${words[i]}" == -* )); do
          (( i++ ))
        done
        if (( i > $#words )); then
          __zlc_command_words=(arch)
          return 0
        fi
        continue
        ;;
      *)
        break
        ;;
    esac
  done

  (( i <= $#words )) || return 1

  while (( i <= $#words )); do
    __zlc_command_words+=("${words[i]}")
    (( i++ ))
  done

  [[ -n ${__zlc_command_words[1]:-} ]]
}

__zlc_has_arg() {
  emulate -L zsh

  local needle="$1"
  shift

  local arg
  for arg in "$@"; do
    [[ "$arg" == "$needle" ]] && return 0
  done

  return 1
}

__zlc_command_in_array() {
  emulate -L zsh

  local command_name="${1:t}"
  shift

  local item
  for item in "$@"; do
    [[ "$command_name" == "$item" ]] && return 0
  done

  return 1
}

__zlc_has_combined_short_flag() {
  emulate -L zsh

  local flag="$1"
  shift

  local arg
  for arg in "$@"; do
    [[ "$arg" == --* ]] && continue
    [[ "$arg" == -* && "$arg" == *"$flag"* ]] && return 0
  done

  return 1
}

__zlc_has_non_option_arg() {
  emulate -L zsh

  local arg
  for arg in "$@"; do
    [[ "$arg" == -- ]] && return 0
    [[ "$arg" != -* ]] && return 0
  done

  return 1
}

__zlc_looks_like_program_path() {
  emulate -L zsh

  local command_path="$1"

  [[ "$command_path" == */* ]]
}

__zlc_shell_invocation_has_program() {
  emulate -L zsh

  __zlc_has_arg -c "$@" && return 0
  __zlc_has_combined_short_flag c "$@" && return 0
  __zlc_has_non_option_arg "$@" && return 0

  return 1
}

__zlc_python_invocation_has_program() {
  emulate -L zsh

  local arg
  local next_is_module=0

  for arg in "$@"; do
    if (( next_is_module )); then
      case "$arg" in
        IPython|bpython|ptpython|pdb|ipdb)
          return 1
          ;;
      esac
      return 0
    fi

    case "$arg" in
      -i)
        return 1
        ;;
      -c)
        return 0
        ;;
      -m)
        next_is_module=1
        ;;
      -*)
        ;;
      *)
        return 0
        ;;
    esac
  done

  return 1
}

__zlc_node_invocation_has_program() {
  emulate -L zsh

  local arg
  for arg in "$@"; do
    case "$arg" in
      -e|--eval|--print)
        return 0
        ;;
      inspect)
        return 1
        ;;
      -*)
        ;;
      *)
        return 0
        ;;
    esac
  done

  return 1
}

__zlc_runtime_invocation_has_program() {
  emulate -L zsh

  local arg
  for arg in "$@"; do
    case "$arg" in
      -c|-e|-E|-r|--eval|--execute)
        return 0
        ;;
      -*)
        ;;
      *)
        return 0
        ;;
    esac
  done

  return 1
}

__zlc_is_log_command() {
  emulate -L zsh

  local command_path="$1"
  local command_name="${command_path:t}"
  shift

  __zlc_looks_like_program_path "$command_path" && return 0

  case "$command_name" in
    sh|bash|zsh|dash|ksh)
      __zlc_shell_invocation_has_program "$@" && return 0
      return 1
      ;;
    python|python2|python3|pypy|pypy3)
      __zlc_python_invocation_has_program "$@" && return 0
      return 1
      ;;
    node)
      __zlc_node_invocation_has_program "$@" && return 0
      return 1
      ;;
    ruby|perl|php|lua|luajit|R|Rscript|julia|swift|dart|deno|bun|ts-node|racket|guile|sbcl|clisp|ocaml|runghc)
      __zlc_runtime_invocation_has_program "$@" && return 0
      return 1
      ;;
  esac

  __zlc_command_in_array "$command_name" "${ZSH_LOG_COPY_CAPTURE_COMMANDS[@]}"
}

__zlc_should_capture() {
  emulate -L zsh

  [[ -z ${ZSH_LOG_COPY_DISABLE:-} ]] || return 1

  local command_text
  local command_name
  local saw_command=0
  local saw_log_command=0

  for command_text in "$@"; do
    [[ -n "$command_text" ]] || continue
    __zlc_resolve_command_words "$command_text" || continue

    command_name="${__zlc_command_words[1]:t}"
    saw_command=1

    case "$command_name" in
      copylast|zsh-log-copy-enable|zsh-log-copy-disable|__zlc_*)
        return 1
        ;;
    esac

    if [[ -n ${ZSH_LOG_COPY_CAPTURE_ALL:-} ]]; then
      saw_log_command=1
      continue
    fi

    __zlc_is_log_command "${__zlc_command_words[1]}" "${__zlc_command_words[@]:1}" && saw_log_command=1
  done

  (( saw_command && saw_log_command ))
}

__zlc_tee_stdout() {
  emulate -L zsh
  command tee -a "$1"
}

__zlc_tee_stderr() {
  emulate -L zsh
  command tee -a "$1" >&2
}

__zlc_cleanup_fifos() {
  emulate -L zsh

  [[ -n "$__zlc_stdout_fifo" ]] && command rm -f "$__zlc_stdout_fifo" 2>/dev/null
  [[ -n "$__zlc_stderr_fifo" ]] && command rm -f "$__zlc_stderr_fifo" 2>/dev/null
  [[ -n "$__zlc_stdout_done" ]] && command rm -f "$__zlc_stdout_done" 2>/dev/null
  [[ -n "$__zlc_stderr_done" ]] && command rm -f "$__zlc_stderr_done" 2>/dev/null

  __zlc_stdout_fifo=""
  __zlc_stderr_fifo=""
  __zlc_stdout_done=""
  __zlc_stderr_done=""
}

__zlc_wait_for_tees() {
  emulate -L zsh

  local i

  for i in {1..1000}; do
    [[ -e "$__zlc_stdout_done" && -e "$__zlc_stderr_done" ]] && return 0
    command sleep 0.01
  done

  return 1
}

__zlc_restore_fds() {
  emulate -L zsh

  (( __zlc_active )) || return 0

  exec >&$__zlc_stdout_fd 2>&$__zlc_stderr_fd
  __zlc_wait_for_tees

  exec {__zlc_stdout_fd}>&- {__zlc_stderr_fd}>&-
  __zlc_cleanup_fifos

  __zlc_active=0
  __zlc_stdout_fd=-1
  __zlc_stderr_fd=-1
  __zlc_current_log=""
}

__zlc_preexec() {
  emulate -L zsh

  __zlc_should_capture "$@" || return 0

  command mkdir -p -- "$ZSH_LOG_COPY_SESSION_DIR" 2>/dev/null || return 0
  : >| "$ZSH_LOG_COPY_LAST_LOG" 2>/dev/null || return 0
  print -r -- "$1" >| "${ZSH_LOG_COPY_SESSION_DIR}/last-command.txt" 2>/dev/null

  ZSH_LOG_COPY_LAST_COMMAND="$1"
  __zlc_current_log="$ZSH_LOG_COPY_LAST_LOG"
  __zlc_stdout_fifo="${ZSH_LOG_COPY_SESSION_DIR}/stdout.$$.${RANDOM}.fifo"
  __zlc_stderr_fifo="${ZSH_LOG_COPY_SESSION_DIR}/stderr.$$.${RANDOM}.fifo"
  __zlc_stdout_done="${ZSH_LOG_COPY_SESSION_DIR}/stdout.$$.${RANDOM}.done"
  __zlc_stderr_done="${ZSH_LOG_COPY_SESSION_DIR}/stderr.$$.${RANDOM}.done"

  exec {__zlc_stdout_fd}>&1 {__zlc_stderr_fd}>&2 || return 0

  command mkfifo "$__zlc_stdout_fifo" "$__zlc_stderr_fifo" 2>/dev/null || {
    exec {__zlc_stdout_fd}>&- {__zlc_stderr_fd}>&-
    __zlc_stdout_fd=-1
    __zlc_stderr_fd=-1
    __zlc_cleanup_fifos
    return 0
  }

  {
    __zlc_tee_stdout "$__zlc_current_log" < "$__zlc_stdout_fifo" >&$__zlc_stdout_fd
    print -r -- done >| "$__zlc_stdout_done"
  } &!

  {
    __zlc_tee_stderr "$__zlc_current_log" < "$__zlc_stderr_fifo" >&$__zlc_stderr_fd
    print -r -- done >| "$__zlc_stderr_done"
  } &!

  __zlc_active=1

  exec > "$__zlc_stdout_fifo" 2> "$__zlc_stderr_fifo" || __zlc_restore_fds
}

__zlc_precmd() {
  emulate -L zsh

  local last_status=$?

  if (( __zlc_active )); then
    ZSH_LOG_COPY_LAST_STATUS="$last_status"
    __zlc_restore_fds
  fi

  return "$last_status"
}

__zlc_clipboard_copy() {
  emulate -L zsh

  local file="$1"

  if (( $+commands[pbcopy] )); then
    command pbcopy < "$file"
  elif (( $+commands[wl-copy] )); then
    command wl-copy < "$file"
  elif (( $+commands[xclip] )); then
    command xclip -selection clipboard < "$file"
  elif (( $+commands[xsel] )); then
    command xsel --clipboard --input < "$file"
  elif (( $+commands[clip.exe] )); then
    command clip.exe < "$file"
  elif __zlc_clipboard_copy_osc52 "$file"; then
    return 0
  else
    print -u2 "copylast: no clipboard command found (tried pbcopy, wl-copy, xclip, xsel, clip.exe, OSC 52)"
    return 127
  fi
}

__zlc_clipboard_copy_osc52() {
  emulate -L zsh

  local file="$1"
  local encoded sequence

  [[ -r "$file" ]] || return 1
  [[ -w /dev/tty ]] || return 1
  (( $+commands[base64] )) || return 1

  encoded="$(command base64 < "$file" 2>/dev/null | command tr -d '\r\n')" || return 1
  [[ -n "$encoded" ]] || return 1

  sequence=$'\e]52;c;'"$encoded"$'\a'

  if [[ -n ${TMUX:-} ]]; then
    # tmux requires wrapping OSC sequences for passthrough.
    printf '\033Ptmux;\033%s\033\\' "$sequence" > /dev/tty
  else
    printf '%s' "$sequence" > /dev/tty
  fi
}

__zlc_sanitize_log() {
  emulate -L zsh

  local input="$1"
  local output="$2"

  [[ -r "$input" ]] || return 1

  if (( $+commands[perl] )); then
    command perl -0pe '
      s/\e\][^\a]*(?:\a|\e\\)//gs;
      s/\e[PX^_].*?\e\\//gs;
      s/\e\[[0-?]*[ -\/]*[@-~]//g;
      s/\e[@-_]//g;
    ' < "$input" >| "$output"
  elif (( $+commands[python3] )); then
    command python3 -c '
import re
import sys
data = sys.stdin.buffer.read().decode("utf-8", "replace")
data = re.sub(r"\x1b\][^\x07]*(?:\x07|\x1b\\)", "", data, flags=re.S)
data = re.sub(r"\x1b[PX^_].*?\x1b\\", "", data, flags=re.S)
data = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", data)
data = re.sub(r"\x1b[@-_]", "", data)
sys.stdout.write(data)
' < "$input" >| "$output"
  else
    command cp "$input" "$output"
  fi
}

__zlc_copy_source_log() {
  emulate -L zsh

  [[ -f "$ZSH_LOG_COPY_LAST_LOG" ]] || return 1
  command mkdir -p -- "$ZSH_LOG_COPY_SESSION_DIR" 2>/dev/null || return 1
  __zlc_sanitize_log "$ZSH_LOG_COPY_LAST_LOG" "$ZSH_LOG_COPY_SANITIZED_LOG" || return 1
  print -r -- "$ZSH_LOG_COPY_SANITIZED_LOG"
}

copylast() {
  emulate -L zsh

  local copy_source

  case "${1:-}" in
    -h|--help)
      print -r -- "usage: copylast [--print|--path|--help]"
      print -r -- "copies the last captured command output from this zsh session"
      return 0
      ;;
    -p|--print)
      copy_source="$(__zlc_copy_source_log)" || {
        print -u2 "copylast: no captured output in this zsh session"
        return 1
      }
      if [[ -f "$copy_source" ]]; then
        command cat -- "$copy_source"
        return $?
      fi
      print -u2 "copylast: no captured output in this zsh session"
      return 1
      ;;
    --path)
      print -r -- "$ZSH_LOG_COPY_LAST_LOG"
      return 0
      ;;
    "")
      ;;
    *)
      print -u2 "copylast: unknown option: $1"
      print -u2 "usage: copylast [--print|--path|--help]"
      return 2
      ;;
  esac

  if [[ ! -s "$ZSH_LOG_COPY_LAST_LOG" ]]; then
    print -u2 "copylast: no captured output in this zsh session"
    return 1
  fi

  copy_source="$(__zlc_copy_source_log)" || return $?

  if [[ ! -s "$copy_source" ]]; then
    print -u2 "copylast: no captured output in this zsh session"
    return 1
  fi

  __zlc_clipboard_copy "$copy_source" || return $?

  local bytes
  bytes="$(command wc -c < "$copy_source" 2>/dev/null)"
  bytes="${bytes//[[:space:]]/}"

  print -r -- "copylast: copied ${bytes:-0} bytes"
}

cpl() {
  copylast "$@"
}

zsh-log-copy-disable() {
  typeset -g ZSH_LOG_COPY_DISABLE=1
}

zsh-log-copy-enable() {
  unset ZSH_LOG_COPY_DISABLE
}

add-zsh-hook preexec __zlc_preexec

# Restore stdout/stderr before prompt themes and terminal integrations print
# title updates or OSC sequences from their own precmd hooks.
add-zsh-hook -d precmd __zlc_precmd 2>/dev/null
precmd_functions=(__zlc_precmd ${precmd_functions:#__zlc_precmd})
