#!/usr/bin/env bash

# File        : debup.sh
# Description : Debian-based system update script
# Copyright   : (c) 2025, Gergely Szabo
# License     : MIT
#
# 'debup' acts a command-line interface to update different components of your
# Debian-based system. It is as a front-end wrapper for the different package
# managers' 'update' command.
#
# Usage:
#   Source debup.sh in your ~/.bashrc or ~/.bash_profile to make it available
#   as a CLI command.
#
# Syntax:
#   debup [OPTION]

##
## PRINT MESSAGE TYPES
##

info() {
    echo -e "\e[1;34m:: \e[1;37m$1\e[0m" >&1
}

warn() {
    echo -e "\e[1;33m:: \e[1;37m$1\e[0m" >&1
}

err() {
    echo -e "\e[1;31m:: \e[1;37m$1\e[0m" >&2
}

usage() {
    cat <<EOF
DEBUP -- A shell script for keeping your Debian-based systems up to date.

Usage: debup [OPTION]

Options:
  -c, --check-updates
          Search for package updates without installing them
  -f, --full, (empty option)
          Perform full system update
  -s, --system
          Update the operating system packages only
  -t, --toolchain
          Update developer toolchain packages only
  -u, --universal
          Update universal package formats only
  -h, --help
          Display this message
EOF
}

##
## GET_ PACKAGE MANAGERS & UPDATES
##

get_toolchain_managers() {
    toolchain_updates=()

    if command -v rustup &> /dev/null; then
        rustup_updates=$(rustup check | grep -v 'Up to date' | wc -l)
        toolchain_updates+=("Rust (${rustup_updates})")

        # It would be nice to gather Cargo package updates, too, but it isn't
        # possible yet -- there is no 'cargo check-updates' equivalent. Maybe
        # when '--dry-run' gets implemented:
        # https://github.com/rust-lang/cargo/issues/11123
    fi

    if command -v go &> /dev/null; then
        go_local_version="$(go version | awk '{print $3}' | sed 's/go//')"
        go_latest_version="$(curl -s https://go.dev/VERSION?m=text | grep -oP 'go\K[0-9.]+')"

        if [[ "$go_local_version" != "$go_latest_version" ]]; then
            toolchain_updates+=("Go (${go_local_version} -> ${go_latest_version})")
        else
            toolchain_updates+=("Go (0)")
        fi
    fi

    return 0
}

get_universal_package_managers() {
    universal_package_updates=()

    if command -v flatpak &> /dev/null; then
        flatpak_updates=$(flatpak remote-ls --updates | wc -l)
        universal_package_updates+=("Flatpak (${flatpak_updates})")
    fi

    return 0
}

get_updates() {
    sudo apt update &> /dev/null
    info "Searching for system updates..."

    get_universal_package_managers
    if [[ ${#universal_package_updates[@]} -gt 0 ]]; then
        info "Searching for universal package updates..."
    fi

    get_toolchain_managers
    if [[ ${#toolchain_updates[@]} -gt 0 ]]; then
        info "Searching for developer toolchain updates..."
    fi

    echo -e "\n          \e[1;32mSystem\e[0m $(cat /etc/os-release | grep -i pretty_name | cut -d= -f2 | tr -d '"')"
    echo -e "     \e[1;32mAPT version\e[0m $(apt --version | awk '{print $2}')"
    echo -e "  \e[1;32mSystem Updates\e[0m $(apt list --upgradable 2> /dev/null | awk 'NR>1' | wc -l)"
    echo -e "   \e[1;32mOther Updates\e[0m ${universal_package_updates[*]:-"--"}"
    echo -e "                 ${toolchain_updates[*]:-}"

    return 0
}

##
## UPDATE_ SYSTEM COMPONENTS & SOFTWARE
##

update_toolchain_packages() {
    get_toolchain_managers
    if [[ -n "${toolchain_updates[*]}" ]]; then
        if [[ "$rustup_updates" -gt 0 ]]; then
            info "Installing Rust updates..."
            rustup update
            info "Rust has been updated."
        fi

        # Vanilla Rust doesn't have a 'cargo update' equivalent.
        # The method of updating installed packages is using
        # 'cargo install' to install the latest available version
        # of an already installed package.
        cargo install $(cargo install --list | \
        grep -E '^[a-z0-9_-]+ v[0-9.]+:$' | \
        cut -f1 -d' ') &> /dev/null

        if [[ "$go_local_version" != "$go_latest_version" ]]; then
            local go_install_dir="$(command -v go | sed 's|/go.*$||')"

            if [[ "$go_install_dir" == "/usr/local" ]]; then
                warn "Detected system-wide installation of Go. These are not supported right now, skipping updates."
                return 0
            fi

            info "Installing Go updates..."
            wget "https://go.dev/dl/go$go_latest_version.linux-amd64.tar.gz" -O /tmp/go.tar.gz

            if [[ $? != 0 ]]; then
                err "Failed to download the latest Go version. Please check the output for details."
                return 1
            fi

            # Remove any previous installations as recommended by
            # https://go.dev/doc/install.
            rm -rf "$go_install_dir/go" &>/dev/null
            tar -C "$go_install_dir" -xzf /tmp/go.tar.gz

            if [[ $? == 0 ]]; then
                info "Go has been updated."
            else
                err "Failed to update Go. Please check the output for details."
                return 1
            fi
        fi
    else
        warn "No developer toolchains were detected. Skipping updates."
        return 0
    fi

    return $?
}

update_universal_packages() {
    get_universal_package_managers
    if [[ -n "${universal_package_updates[*]}" ]]; then
        if [[ "$flatpak_updates" != 0 ]]; then
            info "Installing Flatpak updates..."
            flatpak update -y
            info "Flatpak packages have been updated."
        fi
    else
        warn "No universal package manager was detected. Skipping updates."
        return 0
    fi

    return $?
}

update_system_packages() {
    sudo apt update &> /dev/null
    if [[ $(apt list --upgradable 2>/dev/null | wc -l) -gt 1 ]]; then
        info "Installing system updates..."
        sudo apt upgrade -y

        if [[ "$(sudo apt autoremove --dry-run --assume-no | \
        grep "Removing:" | \
        awk '{print $2}' | tr -d ',')" -gt 0 ]]; then
            info "Cleaning up packages..."
            sudo apt autoremove -y
        fi
        info "System packages have been updated."
    fi

    return $?
}

##
## MAIN FUNCTION
##

main() {
    if [[ -z $BASH_VERSION ]]; then
        echo "This script requires bash to run."
        return 1
    fi

    command="$1"
    case "$command" in
        -h|--help) usage ;;
        -c|--check-updates) get_updates ;;
        -s|--system) update_system_packages ;;
        -t|--toolchain) update_toolchain_packages ;;
        -u|--universal) update_universal_packages ;;
        -f|--full|"")
            get_updates && \
            update_system_packages && \
            update_universal_packages && \
            update_toolchain_packages
            ;;
        *)
            err "Invalid command: $command"
            err "Run 'debup --help' for available commands."
            return 0
            ;;
    esac
}

debup() {
    main "$@"
}
