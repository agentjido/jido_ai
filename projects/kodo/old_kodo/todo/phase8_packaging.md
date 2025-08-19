# Phase 8: Packaging & Distribution

## Overview
Create a complete packaging and distribution system for Kodo, including Mix releases, escript generation, cross-platform binaries, and installation procedures.

## Tasks

### 1. Mix Release Configuration (`rel/`)

#### Release Configuration (`rel/env.sh.eex`, `rel/env.bat.eex`)
```bash
# Environment setup for Kodo release
export KODO_HOME="${RELEASE_ROOT}"
export KODO_CONFIG_DIR="${HOME}/.config/kodo"
export KODO_DATA_DIR="${HOME}/.local/share/kodo"
export KODO_CACHE_DIR="${HOME}/.cache/kodo"

# Set up VFS root directory
export KODO_VFS_ROOT="${KODO_DATA_DIR}/vfs"

# Default shell configuration
export KODO_DEFAULT_SHELL="true"
export KODO_HISTORY_SIZE="1000"
```

#### Release Configuration (`rel/config.exs`)
```elixir
import Config

config :kodo,
  release_mode: true,
  config_dir: System.get_env("KODO_CONFIG_DIR") || "~/.config/kodo",
  data_dir: System.get_env("KODO_DATA_DIR") || "~/.local/share/kodo",
  vfs_root: System.get_env("KODO_VFS_ROOT") || "~/.local/share/kodo/vfs",
  history_file: "~/.kodo_history",
  config_file: "~/.kodorc"

config :logger,
  level: :info,
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]
```

#### Update `mix.exs` for Release
```elixir
def project do
  [
    app: :kodo,
    version: "1.0.0",
    elixir: "~> 1.14",
    start_permanent: Mix.env() == :prod,
    deps: deps(),
    releases: releases(),
    escript: escript(),
    preferred_cli_env: [release: :prod]
  ]
end

defp releases do
  [
    kodo: [
      include_executables_for: [:unix, :windows],
      applications: [runtime_tools: :permanent],
      steps: [:assemble, :tar],
      strip_beams: Mix.env() == :prod
    ]
  ]
end

defp escript do
  [
    main_module: Kodo.CLI,
    name: "kodo",
    embed_elixir: true,
    emu_args: "-noshell -noinput"
  ]
end
```

### 2. Command Line Interface (`lib/kodo/cli.ex`)

#### CLI Entry Point
```elixir
defmodule Kodo.CLI do
  @moduledoc """
  Command line interface for Kodo shell.
  """

  def main(args) do
    # Parse command line arguments
    case parse_args(args) do
      {:interactive, opts} -> start_interactive_shell(opts)
      {:script, script_path, script_args, opts} -> execute_script(script_path, script_args, opts)
      {:command, command, opts} -> execute_command(command, opts)
      {:version} -> show_version()
      {:help} -> show_help()
      {:error, message} -> show_error_and_exit(message)
    end
  end

  defp parse_args(args) do
    OptionParser.parse(args,
      strict: [
        help: :boolean,
        version: :boolean,
        command: :string,
        interactive: :boolean,
        login: :boolean,
        errexit: :boolean,
        xtrace: :boolean,
        nounset: :boolean,
        config: :string,
        no_config: :boolean
      ],
      aliases: [
        h: :help,
        v: :version,
        c: :command,
        i: :interactive,
        l: :login,
        e: :errexit,
        x: :xtrace,
        u: :nounset
      ]
    )
  end

  defp start_interactive_shell(opts) do
    # Initialize and start interactive shell
    {:ok, session_id} = Kodo.Shell.start(opts)
    
    # Load configuration
    unless opts[:no_config] do
      load_config(session_id, opts[:config])
    end
    
    # Start REPL
    Kodo.Transport.EnhancedIEx.start_repl(session_id, opts)
  end

  defp execute_script(script_path, script_args, opts) do
    # Execute script file and exit with status
    {:ok, session_id} = Kodo.Shell.start(opts)
    
    result = Kodo.Core.ScriptExecutor.execute_script(script_path, script_args, %{session_id: session_id})
    
    case result do
      {:ok, _output, exit_status} -> System.halt(exit_status)
      {:error, reason, exit_status} -> 
        IO.puts(:stderr, "kodo: #{reason}")
        System.halt(exit_status)
    end
  end

  defp execute_command(command, opts) do
    # Execute single command and exit
    {:ok, session_id} = Kodo.Shell.start(opts)
    
    case Kodo.Shell.eval(session_id, command) do
      {:ok, output} -> 
        IO.puts(output)
        System.halt(0)
      {:error, reason} -> 
        IO.puts(:stderr, "kodo: #{reason}")
        System.halt(1)
    end
  end

  defp show_version do
    version = Application.spec(:kodo, :vsn) |> to_string()
    IO.puts("Kodo #{version}")
    IO.puts("Elixir-native shell environment")
    System.halt(0)
  end

  defp show_help do
    IO.puts("""
    Kodo - Elixir-native shell environment

    Usage:
      kodo [OPTIONS]                    Start interactive shell
      kodo [OPTIONS] SCRIPT [ARGS...]   Execute script file
      kodo [OPTIONS] -c COMMAND         Execute command string

    Options:
      -h, --help           Show this help message
      -v, --version        Show version information
      -i, --interactive    Force interactive mode
      -l, --login          Start as login shell
      -c, --command CMD    Execute command and exit
      -e, --errexit        Exit immediately on command failure
      -x, --xtrace         Print commands before executing
      -u, --nounset        Error on unset variables
      --config FILE        Use specific config file
      --no-config          Don't load config files

    Examples:
      kodo                             # Start interactive shell
      kodo script.kodo arg1 arg2       # Execute script with arguments
      kodo -c "ls -la | grep .ex"      # Execute single command
      kodo -e -x script.kodo           # Execute with error checking and tracing

    Configuration:
      Config file: ~/.kodorc
      History file: ~/.kodo_history
      Data directory: ~/.local/share/kodo

    For more information, visit: https://github.com/your-org/kodo
    """)
    System.halt(0)
  end
end
```

### 3. Installation Scripts (`scripts/`)

#### Unix Installation Script (`scripts/install.sh`)
```bash
#!/bin/bash
set -e

KODO_VERSION=${KODO_VERSION:-"1.0.0"}
INSTALL_DIR=${INSTALL_DIR:-"/usr/local/bin"}
RELEASE_URL="https://github.com/your-org/kodo/releases/download/v${KODO_VERSION}"

# Detect platform
case "$(uname -s)" in
    Linux*)     PLATFORM=linux;;
    Darwin*)    PLATFORM=macos;;
    *)          echo "Unsupported platform: $(uname -s)"; exit 1;;
esac

case "$(uname -m)" in
    x86_64)     ARCH=x86_64;;
    arm64)      ARCH=arm64;;
    aarch64)    ARCH=arm64;;
    *)          echo "Unsupported architecture: $(uname -m)"; exit 1;;
esac

BINARY_NAME="kodo-${PLATFORM}-${ARCH}"
DOWNLOAD_URL="${RELEASE_URL}/${BINARY_NAME}"

echo "Installing Kodo ${KODO_VERSION} for ${PLATFORM}-${ARCH}..."

# Download binary
echo "Downloading from ${DOWNLOAD_URL}..."
curl -L -o kodo "${DOWNLOAD_URL}"

# Make executable
chmod +x kodo

# Move to install directory
if [ -w "${INSTALL_DIR}" ]; then
    mv kodo "${INSTALL_DIR}/kodo"
else
    echo "Installing to ${INSTALL_DIR} (requires sudo)..."
    sudo mv kodo "${INSTALL_DIR}/kodo"
fi

echo "Kodo installed successfully to ${INSTALL_DIR}/kodo"
echo "Run 'kodo --help' to get started"
```

#### Windows Installation Script (`scripts/install.ps1`)
```powershell
param(
    [string]$Version = "1.0.0",
    [string]$InstallDir = "$env:LOCALAPPDATA\Programs\Kodo"
)

$ErrorActionPreference = "Stop"

$Platform = "windows"
$Arch = if ([Environment]::Is64BitOperatingSystem) { "x86_64" } else { "x86" }
$BinaryName = "kodo-$Platform-$Arch.exe"
$ReleaseUrl = "https://github.com/your-org/kodo/releases/download/v$Version"
$DownloadUrl = "$ReleaseUrl/$BinaryName"

Write-Host "Installing Kodo $Version for $Platform-$Arch..."

# Create install directory
if (!(Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
}

# Download binary
$BinaryPath = Join-Path $InstallDir "kodo.exe"
Write-Host "Downloading from $DownloadUrl..."
Invoke-WebRequest -Uri $DownloadUrl -OutFile $BinaryPath

# Add to PATH if not already there
$CurrentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($CurrentPath -notlike "*$InstallDir*") {
    $NewPath = "$CurrentPath;$InstallDir"
    [Environment]::SetEnvironmentVariable("PATH", $NewPath, "User")
    Write-Host "Added $InstallDir to PATH"
}

Write-Host "Kodo installed successfully to $BinaryPath"
Write-Host "Run 'kodo --help' to get started"
Write-Host "Note: You may need to restart your terminal for PATH changes to take effect"
```

### 4. Cross-Platform Binary Generation

#### GitHub Actions Workflow (`.github/workflows/release.yml`)
```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    name: Build for ${{ matrix.os }}-${{ matrix.arch }}
    runs-on: ${{ matrix.runner }}
    strategy:
      matrix:
        include:
          - os: linux
            arch: x86_64
            runner: ubuntu-latest
          - os: linux
            arch: arm64
            runner: ubuntu-latest
          - os: macos
            arch: x86_64
            runner: macos-latest
          - os: macos
            arch: arm64
            runner: macos-latest
          - os: windows
            arch: x86_64
            runner: windows-latest

    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.15'
        otp-version: '26'
    
    - name: Restore dependencies cache
      uses: actions/cache@v3
      with:
        path: deps
        key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
        restore-keys: ${{ runner.os }}-mix-
    
    - name: Install dependencies
      run: mix deps.get --only prod
    
    - name: Build release
      env:
        MIX_ENV: prod
      run: mix release --overwrite
    
    - name: Create escript
      env:
        MIX_ENV: prod
      run: mix escript.build
    
    - name: Rename binary
      run: |
        if [ "${{ matrix.os }}" = "windows" ]; then
          mv kodo kodo-${{ matrix.os }}-${{ matrix.arch }}.exe
        else
          mv kodo kodo-${{ matrix.os }}-${{ matrix.arch }}
        fi
      shell: bash
    
    - name: Upload binary
      uses: actions/upload-artifact@v3
      with:
        name: kodo-${{ matrix.os }}-${{ matrix.arch }}
        path: kodo-${{ matrix.os }}-${{ matrix.arch }}*

  release:
    needs: build
    runs-on: ubuntu-latest
    steps:
    - name: Download all artifacts
      uses: actions/download-artifact@v3
    
    - name: Create Release
      uses: softprops/action-gh-release@v1
      with:
        files: |
          kodo-*/kodo-*
        generate_release_notes: true
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### 5. Package Managers Integration

#### Homebrew Formula (`Formula/kodo.rb`)
```ruby
class Kodo < Formula
  desc "Elixir-native shell environment"
  homepage "https://github.com/your-org/kodo"
  url "https://github.com/your-org/kodo/releases/download/v1.0.0/kodo-macos-x86_64"
  sha256 "..." # Generate actual SHA256
  license "MIT"

  def install
    bin.install "kodo-macos-x86_64" => "kodo"
  end

  test do
    assert_match "Kodo", shell_output("#{bin}/kodo --version")
  end
end
```

#### Arch Linux PKGBUILD (`PKGBUILD`)
```bash
pkgname=kodo
pkgver=1.0.0
pkgrel=1
pkgdesc="Elixir-native shell environment"
arch=('x86_64' 'aarch64')
url="https://github.com/your-org/kodo"
license=('MIT')
depends=()
source=("$pkgname-$pkgver::https://github.com/your-org/kodo/releases/download/v$pkgver/kodo-linux-x86_64")
sha256sums=('SKIP')

package() {
    install -Dm755 "$srcdir/$pkgname-$pkgver" "$pkgdir/usr/bin/kodo"
}
```

#### Snap Package (`snap/snapcraft.yaml`)
```yaml
name: kodo
version: '1.0.0'
summary: Elixir-native shell environment
description: |
  Kodo is a modern shell environment built in Elixir, providing
  a cross-platform, extensible shell experience with virtual
  filesystem support and native Elixir integration.

grade: stable
confinement: strict

parts:
  kodo:
    plugin: dump
    source: .
    organize:
      kodo: bin/kodo
    stage-packages:
      - libc6

apps:
  kodo:
    command: bin/kodo
    plugs: [home, network]
```

### 6. Documentation and Distribution

#### README Updates
```markdown
# Kodo - Elixir-Native Shell

A modern, cross-platform shell environment built in Elixir.

## Installation

### Quick Install (Unix/macOS)
```bash
curl -fsSL https://raw.githubusercontent.com/your-org/kodo/main/scripts/install.sh | bash
```

### Quick Install (Windows)
```powershell
iwr -useb https://raw.githubusercontent.com/your-org/kodo/main/scripts/install.ps1 | iex
```

### Package Managers

**Homebrew (macOS/Linux):**
```bash
brew install your-org/tap/kodo
```

**Arch Linux:**
```bash
yay -S kodo
```

**Snap:**
```bash
sudo snap install kodo
```

### Manual Installation

Download the appropriate binary for your platform from the [releases page](https://github.com/your-org/kodo/releases).

## Usage

Start interactive shell:
```bash
kodo
```

Execute script:
```bash
kodo script.kodo
```

Execute command:
```bash
kodo -c "ls -la"
```
```

#### User Manual (`docs/manual.md`)
```markdown
# Kodo User Manual

## Getting Started
## Configuration
## Built-in Commands
## Scripting
## VFS and Filesystem Integration
## Customization
## Troubleshooting
```

### 7. Update Mechanism

#### Auto-Update System (`lib/kodo/core/updater.ex`)
```elixir
defmodule Kodo.Core.Updater do
  # Check for updates
  def check_for_updates()
  
  # Download and install update
  def update_to_version(version)
  
  # Verify update integrity
  def verify_update(binary_path, checksum)
  
  # Backup current version before update
  def backup_current_version()
  
  # Rollback to previous version
  def rollback_update()
end
```

#### Update Command
```elixir
defcommand "update" do
  @description "Update Kodo to latest version"
  @usage "update [--check-only] [--version=VERSION]"
  @meta [:builtin]
  
  def execute(args, context) do
    # Check for updates and optionally install
  end
end
```

### 8. Testing Release Process

#### Release Testing (`test/release/`)
```elixir
defmodule ReleaseTest do
  use ExUnit.Case
  
  test "escript builds successfully" do
    assert {_output, 0} = System.cmd("mix", ["escript.build"], env: [{"MIX_ENV", "prod"}])
    assert File.exists?("kodo")
  end
  
  test "release builds successfully" do
    assert {_output, 0} = System.cmd("mix", ["release", "--overwrite"], env: [{"MIX_ENV", "prod"}])
    assert File.exists?("_build/prod/rel/kodo")
  end
  
  test "CLI shows version" do
    {output, 0} = System.cmd("./kodo", ["--version"])
    assert output =~ "Kodo"
  end
  
  test "CLI shows help" do
    {output, 0} = System.cmd("./kodo", ["--help"])
    assert output =~ "Usage:"
  end
end
```

### 9. Deployment and Distribution

#### Docker Container (`Dockerfile`)
```dockerfile
FROM elixir:1.15-alpine AS builder

WORKDIR /app
COPY mix.exs mix.lock ./
COPY lib lib
COPY config config

ENV MIX_ENV=prod
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only prod && \
    mix release

FROM alpine:3.18
RUN apk add --no-cache openssl ncurses-libs
WORKDIR /app
COPY --from=builder /app/_build/prod/rel/kodo ./
CMD ["./bin/kodo"]
```

#### Release Automation Script (`scripts/release.sh`)
```bash
#!/bin/bash
set -e

VERSION=$1
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    exit 1
fi

echo "Preparing release $VERSION..."

# Update version in mix.exs
sed -i "s/version: \".*\"/version: \"$VERSION\"/" mix.exs

# Build and test
mix deps.get
mix test
mix dialyzer

# Create git tag
git add mix.exs
git commit -m "Bump version to $VERSION"
git tag "v$VERSION"

# Push to trigger CI
git push origin main
git push origin "v$VERSION"

echo "Release $VERSION created and pushed!"
echo "CI will build and publish binaries automatically."
```

## Success Criteria
- [ ] Mix release builds successfully for production
- [ ] Escript generates working standalone binary
- [ ] Cross-platform binaries created via CI/CD
- [ ] Installation scripts work on all supported platforms
- [ ] Package manager integrations functional
- [ ] Documentation complete and accessible
- [ ] Auto-update mechanism works reliably
- [ ] Release process automated and tested
- [ ] Docker container runs correctly
- [ ] All distribution channels functional

## Example Usage
```bash
# Install via script
curl -fsSL https://install.kodo.sh | bash

# Verify installation
kodo --version
# Output: Kodo 1.0.0

# Start using
kodo
kodo> echo "Hello, World!"
Hello, World!

# Update to latest
kodo update
# Checking for updates...
# Updated to version 1.1.0
```

## Dependencies
- Elixir 1.14+ and OTP 25+
- Mix release system
- Cross-platform CI/CD (GitHub Actions)
- Package manager tooling

## Estimated Time
1-2 weeks for implementation and testing
