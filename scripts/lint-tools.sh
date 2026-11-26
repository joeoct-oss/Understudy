#!/usr/bin/env bash
#
#  lint-tools.sh
#  Understudy
#
#  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
#  Copyright © 2026 Yousef Mohamed. MIT License.
#
# Shared by scripts/lint.sh and scripts/format.sh, which source it. It is the one home for the
# SwiftLint version and the sha256s of its Linux release zips: find_swiftlint installs that version
# into .tools/ (git-ignored) when it is missing, from the GitHub release, with the sha256 checked.
# check_swift_format stops when the toolchain's `swift format` isn't SWIFT_FORMAT_VERSION's major
# and minor, because two versions can format the same file two ways. Waypoint pins the same
# versions in its .mise.toml; an upgrade updates both.
# - SwiftLint comes from $SWIFTLINT, then .tools/bin/swiftlint, then an install.
# - The linted paths are LINT_PATHS.

LINT_PATHS=(Sources Tests Tools Benchmarks ApplePlatforms Swift5Mode Package.swift)
SWIFTLINT_VERSION="0.65.1"
SWIFTLINT_LINUX_AMD64_SHA256="caeed6f4a679c35539ffaf124f6c4ab4a8416917f7d8796279dc52b74026059d"
SWIFTLINT_LINUX_ARM64_SHA256="9ffa52f478e6d8eb485d37d14715ffac90abc81c58f3370d598bf75be05605f8"
SWIFT_FORMAT_VERSION="6.4"

# Installs SWIFTLINT_VERSION into .tools/swiftlint-<version> and links .tools/bin/swiftlint. Linux
# only: the macOS runners and a Mac use their own SwiftLint through $SWIFTLINT.
install_swiftlint() {
    local arch checksum install_dir zip_path
    case "$(uname -m)" in
        x86_64)
            arch="amd64"
            checksum="$SWIFTLINT_LINUX_AMD64_SHA256"
            ;;
        aarch64 | arm64)
            arch="arm64"
            checksum="$SWIFTLINT_LINUX_ARM64_SHA256"
            ;;
        *)
            echo "error: no SwiftLint Linux release for $(uname -m)." >&2
            exit 1
            ;;
    esac
    install_dir=".tools/swiftlint-$SWIFTLINT_VERSION"
    if [[ ! -x "$install_dir/swiftlint" ]]; then
        echo "==> Downloading SwiftLint $SWIFTLINT_VERSION ($arch)"
        zip_path="$(mktemp)"
        curl --fail --silent --show-error --location --proto '=https' --output "$zip_path" \
            "https://github.com/realm/SwiftLint/releases/download/$SWIFTLINT_VERSION/swiftlint_linux_$arch.zip"
        if ! echo "$checksum  $zip_path" | sha256sum --check --quiet -; then
            rm -f "$zip_path"
            echo "error: the SwiftLint download doesn't match the sha256 in scripts/lint-tools.sh." >&2
            exit 1
        fi
        mkdir -p "$install_dir"
        unzip -q -o "$zip_path" -d "$install_dir"
        rm -f "$zip_path"
    fi
    mkdir -p .tools/bin
    ln -sf "../swiftlint-$SWIFTLINT_VERSION/swiftlint" .tools/bin/swiftlint
}

find_swiftlint() {
    if [[ -z "${SWIFTLINT:-}" ]]; then
        if [[ ! -x .tools/bin/swiftlint ]]; then
            if [[ "$(uname -s)" != "Linux" ]]; then
                echo "error: set SWIFTLINT to a SwiftLint $SWIFTLINT_VERSION binary." >&2
                exit 1
            fi
            install_swiftlint
        fi
        SWIFTLINT=.tools/bin/swiftlint
    fi
    local found
    found="$("$SWIFTLINT" version)"
    if [[ "$found" != "$SWIFTLINT_VERSION" ]]; then
        echo "error: SwiftLint $found found, scripts/lint-tools.sh pins $SWIFTLINT_VERSION." >&2
        exit 1
    fi
}

check_swift_format() {
    local found
    found="$(swift format --version)"
    if [[ "$found" != "$SWIFT_FORMAT_VERSION" && "$found" != "$SWIFT_FORMAT_VERSION".* ]]; then
        echo "error: swift format $found found, scripts/lint-tools.sh expects $SWIFT_FORMAT_VERSION." >&2
        exit 1
    fi
}
