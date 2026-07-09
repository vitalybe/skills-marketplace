#!/usr/bin/env bash
# Shared utilities for argc-based scripts

# --- Colors
COLOR_BLACK="\033[0;30m"
COLOR_BLACK_BOLD="\033[1;30m"
COLOR_BLACK_LIGHT="\033[0;90m"

COLOR_RED="\033[0;31m"
COLOR_RED_BOLD="\033[1;31m"
COLOR_RED_LIGHT="\033[0;91m"

COLOR_GREEN="\033[0;32m"
COLOR_GREEN_BOLD="\033[1;32m"
COLOR_GREEN_LIGHT="\033[0;92m"

COLOR_YELLOW="\033[0;33m"
COLOR_YELLOW_BOLD="\033[1;33m"
COLOR_YELLOW_LIGHT="\033[0;93m"

COLOR_BLUE="\033[0;34m"
COLOR_BLUE_BOLD="\033[1;34m"
COLOR_BLUE_LIGHT="\033[0;94m"

COLOR_PURPLE="\033[0;35m"
COLOR_PURPLE_BOLD="\033[1;35m"
COLOR_PURPLE_LIGHT="\033[0;95m"

COLOR_CYAN="\033[0;36m"
COLOR_CYAN_BOLD="\033[1;36m"
COLOR_CYAN_LIGHT="\033[0;96m"

COLOR_WHITE="\033[0;37m"
COLOR_WHITE_BOLD="\033[1;37m"
COLOR_WHITE_LIGHT="\033[0;97m"

COLOR_RESET="\033[0m"


# --- Color helpers ---
color_error() { printf "${COLOR_RED}%s${COLOR_RESET}" "$1"; }
color_warning() { printf "${COLOR_YELLOW}%s${COLOR_RESET}" "$1"; }
color_success() { printf "${COLOR_GREEN_BOLD}%s${COLOR_RESET}" "$1"; }
color_value() { printf "${COLOR_WHITE_LIGHT}%s${COLOR_RESET}" "$1"; }
color_hint() { printf "${COLOR_CYAN}%s${COLOR_RESET}" "$1"; }
color_debug() { printf "${COLOR_BLACK_LIGHT}%s${COLOR_RESET}" "$1"; }

echo_stderr() { echo "$@" >&2; }

# --- Structured logging ---
LOG_PREFIX=""
set_log_prefix() { LOG_PREFIX="$1"; }
log_msg()     { echo_stderr "[${LOG_PREFIX}] $*"; }
log_debug()   { echo_stderr "$(color_debug "[${LOG_PREFIX}]") $(color_debug "$*")"; }
log_value()   { echo_stderr "[${LOG_PREFIX}] $1: $(color_value "$2")"; }
log_success() { echo_stderr "$(color_success "[${LOG_PREFIX}] ✔") $*"; }
log_warn()    { echo_stderr "$(color_warning "[${LOG_PREFIX}]") $*"; }
log_error()   { echo_stderr "$(color_error "[${LOG_PREFIX}]") $*"; }

# Prints git root path or exits with error
require_git_root() {
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo_stderr "$(color_error "Not inside a git repository")"
        exit 1
    }
    echo "$root"
}

# Extract task ID (e.g., STF-123) from a string
extract_task_id() {
    echo "$1" | grep -oE '[A-Za-z]+-[0-9]+' | tail -1 || true
}

# Extract known commands and aliases dynamically from argc annotations
# Usage: extract_known_commands "$0"
# Returns: pipe-separated list of command names and aliases (e.g., "find|f|create|c|list|l")
extract_known_commands() {
    local script_path="$1"

    awk '
      /^# @cmd/ { has_cmd=1; next }
      /^# @alias/ { print $3; next }
      has_cmd && /^[a-z][a-z_-]*\(\)/ {
        match($0, /^([a-z][a-z_-]*)/, arr);
        print arr[1];
        has_cmd=0;
      }
    ' "$script_path" | tr '\n' '|' | sed 's/|$//'
}

# Verify a required command is available; print a helpful hint and exit if not.
# Usage: require_cmd <command> <install-hint>
require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo_stderr "$(color_error "Missing dependency:") '$1' not found. $2"
        exit 1
    fi
}
