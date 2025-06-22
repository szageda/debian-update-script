# Debian Update Script

**Debup** is shell script written in Bash to keep your Debian-based systems up to date. It is as a front-end wrapper for the different package
managers' 'update' command.

**Supported Package Managers**

- APT system package manager
- Universal package manager: Flatpak
- Rust (`rustup`), Cargo, Go.

## Installation

1. Clone the repository to your computer.

```shell
git clone --depth 1 https://github.com/szageda/debian-update-script.git ~/.local/bin
```

2. Source `debup.sh` in your `.bashrc`.

```shell
echo -e '\nsource $HOME/.local/bin/debup.sh' >> ~/.bashrc
```

3. Reload your shell environment.

```shell
source ~/.bashrc
```

## Usage & Syntax

```shell
$ debup [OPTION]
```

Run `debup --help` to get the full list of available ptions.
