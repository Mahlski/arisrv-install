#!/usr/bin/env bash
# Claude Code statusLine command
# Format: user@host:cwd (git-branch|state) | model ctx%

input=$(cat)

# --- Working directory (abbreviate home to ~, shorten middle dirs) ---
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
home_dir="$HOME"
# Abbreviate home prefix to ~
display_cwd="${cwd/#$home_dir/\~}"
# Shorten intermediate path components to first letter
IFS='/' read -ra parts <<< "$display_cwd"
shortened=""
last_idx=$(( ${#parts[@]} - 1 ))
for i in "${!parts[@]}"; do
    part="${parts[$i]}"
    if [[ $i -eq 0 || $i -eq $last_idx || -z "$part" ]]; then
        shortened="${shortened}${part}/"
    else
        shortened="${shortened}${part:0:1}/"
    fi
done
# Remove trailing slash
display_cwd="${shortened%/}"
# Fix double slash from root
display_cwd="${display_cwd//\/\//\/}"

# --- Git info ---
git_info=""
if git_branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null); then
    git_state=""
    # Staged changes
    if ! git -C "$cwd" diff --cached --quiet 2>/dev/null; then
        git_state="${git_state}✚"
    fi
    # Dirty (unstaged modifications)
    if ! git -C "$cwd" diff --quiet 2>/dev/null; then
        git_state="${git_state}*"
    fi
    # Untracked files
    if [[ -n $(git -C "$cwd" ls-files --others --exclude-standard 2>/dev/null) ]]; then
        git_state="${git_state}?"
    fi
    if [[ -n "$git_state" ]]; then
        git_info=" (${git_branch}⚡${git_state})"
    else
        git_info=" (${git_branch}✓)"
    fi
fi

# --- Model ---
model=$(echo "$input" | jq -r '.model.display_name // empty')

# --- Context window ---
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_str=""
if [[ -n "$ctx_pct" ]]; then
    ctx_str=$(printf " ctx:%.0f%%" "$ctx_pct")
fi

# --- Session dials + rate limits (one jq pass) ---
# `// ""` not `// empty`: inside an array constructor `empty` DROPS the element and shifts
# every later field into the wrong variable. Same absent-field guard, positionally safe.
# Delimiter is `|` not tab: tab is IFS-whitespace, so `read` would collapse runs of tabs and
# silently drop empty fields. None of these values can contain `|`.
dials=$(echo "$input" | jq -r '[
    (.effort.level // ""),
    (if .fast_mode then "fast" else "" end),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // "")
] | join("|")' 2>/dev/null)
IFS='|' read -r effort fast rl5_pct rl5_reset rl7_pct rl7_reset <<< "$dials"

# `effort` is absent entirely when the model has no effort parameter; `fast_mode` is always
# present but only worth rendering when true.
effort_str=""
[[ -n "$effort" ]] && effort_str=" eff:${effort}"
fast_str=""
[[ -n "$fast" ]] && fast_str=" fast"

# --- Rate-limit windows (subscription auth only; absent until the first API response) ---
# used_percentage is a float (utilization*100), so round before any integer test.
# Reset clock only once a window is nearly full — below that it is noise.
fmt_limit() {
    local label="$1" pct="$2" reset="$3" n clock=""
    [[ -z "$pct" ]] && return 0
    n=$(printf "%.0f" "$pct" 2>/dev/null) || return 0
    [[ -z "$n" ]] && return 0
    if [[ -n "$reset" ]] && (( n >= 80 )); then
        clock=$(date -d "@$reset" +%H:%M 2>/dev/null) && clock="@${clock}"
    fi
    printf " %s:%d%%%s" "$label" "$n" "$clock"
}

# --- Assemble ---
# `uname -n` not `hostname` — hostname binary ships in inetutils, not guaranteed.
user=$(whoami)
host=$(uname -n)

printf "%s@%s:%s%s" "$user" "$host" "$display_cwd" "$git_info"
if [[ -n "$model" ]]; then
    printf " [%s%s%s%s]" "$model" "$effort_str" "$fast_str" "$ctx_str"
fi
fmt_limit "5h" "$rl5_pct" "$rl5_reset"
fmt_limit "7d" "$rl7_pct" "$rl7_reset"
printf "\n"
