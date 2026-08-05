# Minimal fish config for the completion sandbox.
# No user config is loaded here, so the only source of `timew` completions is
# the checked-out timew.fish linked into completions/.

function fish_prompt
    echo -n (set_color brmagenta)"timew-dev"(set_color normal)" "(prompt_pwd)"> "
end
