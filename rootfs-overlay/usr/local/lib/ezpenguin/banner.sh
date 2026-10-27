#!/usr/bin/env bash
# banner.sh — shared EZpenguin ASCII/UX library.
# Sourced by ez-* tools. Provides: ez_banner, ez_box, ez_hr, colors.

# colors (only when stdout is a real tty — keeps pipes/logs clean)
if [[ -t 1 ]]; then
    EZC_RESET='\033[0m'; EZC_BOLD='\033[1m'; EZC_DIM='\033[2m'
    EZC_CYAN='\033[1;36m'; EZC_YELLOW='\033[1;33m'
    EZC_GREEN='\033[1;32m'; EZC_RED='\033[1;31m'; EZC_BLUE='\033[1;34m'
    EZC_WHITE='\033[1;37m'
else
    EZC_RESET=''; EZC_BOLD=''; EZC_DIM=''
    EZC_CYAN=''; EZC_YELLOW=''
    EZC_GREEN=''; EZC_RED=''; EZC_BLUE=''; EZC_WHITE=''
fi

# The penguin (hand-drawn, block-safe for serial consoles)
EZ_LOGO='\n
        .--.      \n
       |o_o |     \n
       |:_/ |     \n
      //   \ \    \n
     (|     | )   \n
    /"\_   _/`\   \n
    \___)=(___/   \n'

ez_logo_print() { # prints the penguin in cyan
    printf '%b' "${EZC_CYAN}${EZ_LOGO}${EZC_RESET}"
}

ez_banner() { # ez_banner [subtitle]
    local sub="${1:-}"
    local ver; ver=$(cat /etc/ezpenguin/version 2>/dev/null || echo '')
    printf '%b' "${EZC_CYAN}${EZ_LOGO}${EZC_RESET}"
    printf '%b' "${EZC_BOLD}     E Z P E N G U I N${EZC_RESET}  ${EZC_DIM}v${ver}${EZC_RESET}\n"
    if [[ -n "$sub" ]]; then
        local width=44
        printf '%b' "${EZC_DIM}  ┌──────────────────────────────────────────┐${EZC_RESET}\n"
        printf '%b' "${EZC_DIM}  │${EZC_RESET} ${EZC_BOLD}%-42s${EZC_RESET} ${EZC_DIM}│${EZC_RESET}\n" "$sub"
        printf '%b' "${EZC_DIM}  └──────────────────────────────────────────┘${EZC_RESET}\n"
    fi
    printf '\n'
}

ez_hr() { # horizontal rule
    printf '%b\n' "${EZC_DIM}────────────────────────────────────────────────${EZC_RESET}"
}

ez_ok()   { printf '%b\n' "${EZC_GREEN}✔${EZC_RESET} $*"; }
ez_warn() { printf '%b\n' "${EZC_YELLOW}⚠${EZC_RESET} $*"; }
ez_fail() { printf '%b\n' "${EZC_RED}✘${EZC_RESET} $*"; }
