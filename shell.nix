# Dev shell for working on the timewarrior fish completions.
#
#   nix-shell            # enter, then run timew-seed and `fish`
#
# Everything is sandboxed under ./.devshell: a fish config dir whose only
# `timew` completions are the checked-out timew.fish, and a throwaway
# timewarrior database. The real ~/.config/fish and ~/.local/share/timewarrior
# are never touched.
{ pkgs ? import <nixpkgs> { } }:

let
  # Scripts rather than shell functions, so they also work from
  # `nix-shell --run '...'` and from inside the sandboxed fish.
  timew-reset = pkgs.writeShellScriptBin "timew-reset" ''
    set -e
    test -n "$TIMEWARRIORDB" || { echo "TIMEWARRIORDB unset - refusing to delete anything" >&2; exit 1; }
    case "$TIMEWARRIORDB" in
      */.devshell/*) ;;
      *) echo "TIMEWARRIORDB is not inside ./.devshell - refusing to delete $TIMEWARRIORDB" >&2; exit 1 ;;
    esac
    rm -rf "$TIMEWARRIORDB"
    mkdir -p "$TIMEWARRIORDB"
  '';

  # Idempotent: wipes the throwaway database first, so re-running it never
  # trips over "You cannot overlap intervals".
  timew-seed = pkgs.writeShellScriptBin "timew-seed" ''
    set -e
    ${timew-reset}/bin/timew-reset
    day=$(date +%Y-%m-%d)
    timew track "''${day}T08:00" - "''${day}T09:00" admin > /dev/null
    timew track "''${day}T10:00" - "''${day}T11:00" work project-a > /dev/null
    timew summary :ids
  '';

  # Non-interactive equivalent of pressing tab: timew-complete 'timew retag '
  timew-complete = pkgs.writeShellScriptBin "timew-complete" ''
    exec ${pkgs.fish}/bin/fish -c "complete -C '$1'"
  '';

  # Reproduce a machine whose `timew help` does not list a given command, which
  # is what makes the base command list leak into a subcommand's completions:
  #   timew-complete-hiding retag 'timew retag '
  timew-complete-hiding = pkgs.writeShellScriptBin "timew-complete-hiding" ''
    set -e
    hidden="$1"
    line="$2"

    # A shim timew whose `help` usage block omits $hidden - exactly the situation
    # on a machine whose timewarrior predates that command. Everything else is
    # passed through to the real binary.
    shim=$(mktemp -d)
    trap 'rm -rf "$shim"' EXIT
    cat > "$shim/timew" <<SHIM
    #!/bin/sh
    if [ "\$1" = help ] && [ \$# -eq 1 ]; then
      ${pkgs.timewarrior}/bin/timew help | grep -v "^ *timew $hidden "
    else
      exec ${pkgs.timewarrior}/bin/timew "\$@"
    fi
    SHIM
    sed -i 's/^    //' "$shim/timew"
    chmod +x "$shim/timew"

    PATH="$shim:$PATH" ${pkgs.fish}/bin/fish -c "complete -C '$line'"
  '';
in
pkgs.mkShell {
  packages = [
    pkgs.fish
    pkgs.timewarrior
    timew-seed
    timew-reset
    timew-complete
    timew-complete-hiding
  ];

  shellHook = ''
    export TIMEW_DEV_ROOT="$PWD/.devshell"
    export XDG_CONFIG_HOME="$TIMEW_DEV_ROOT/config"
    export XDG_DATA_HOME="$TIMEW_DEV_ROOT/data"
    # NOTE: the variable timewarrior reads is TIMEWARRIORDB (no underscores).
    # Get the name wrong and timew silently falls back to
    # ~/.local/share/timewarrior, i.e. your real database.
    export TIMEWARRIORDB="$TIMEW_DEV_ROOT/timew-data"

    mkdir -p "$XDG_CONFIG_HOME/fish/completions" \
             "$XDG_CONFIG_HOME/timewarrior/extensions" \
             "$XDG_DATA_HOME" "$TIMEWARRIORDB"

    # Symlinked, so edits to timew.fish take effect in the next fish session
    # without re-entering the dev shell.
    ln -sfn "$PWD/timew.fish" "$XDG_CONFIG_HOME/fish/completions/timew.fish"
    ln -sfn "$PWD/dev/fish-config.fish" "$XDG_CONFIG_HOME/fish/config.fish"

    # Pre-create the config so timew never prompts to set itself up. If it does
    # prompt, every timew call aborts, the command scrape returns nothing, and
    # *all* completions leak - which looks just like the bug under test.
    touch "$XDG_CONFIG_HOME/timewarrior/timewarrior.cfg"

    echo "timew completion dev shell"
    echo "  timew        $(command -v timew) ($(timew --version 2>/dev/null))"
    echo "  fish         $(command -v fish)"
    echo "  fish config  $XDG_CONFIG_HOME/fish (completions/timew.fish -> ./timew.fish)"
    echo "  timew db     $TIMEWARRIORDB"
    echo
    echo "  timew-seed                      reset + create sample intervals/tags"
    echo "  timew-reset                     wipe the sandbox timewarrior database"
    echo "  timew-complete 'timew resize '  print completions non-interactively"
    echo "  timew-complete-hiding retag 'timew retag '"
    echo "                                  same, pretending 'timew help' omits retag"
    echo "  fish                            sandboxed interactive shell, then tab away"
  '';
}
