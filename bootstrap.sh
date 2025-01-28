#!/usr/bin/env bash
# Copyright (c) 2025, Prasad T
# shellcheck disable=SC2034,SC2155
set -o pipefail

function __is_colorable() {
    if [[ -n ${CLICOLOR_FORCE} ]] && [[ ${CLICOLOR_FORCE} != "0" ]]; then
        return 0
    elif [[ -n ${NO_COLOR} ]] || [[ ${CLICOLOR} == "0" ]]; then
        return 1
    fi

    if [[ (-t 1 && (${TERM} != "dumb" && ${TERM} != "linux")) || ${CI} == "true" || ${GITHUB_ACTIONS} == "true" ]]; then
        return 0
    fi

    return 1
}

function log_debug() {
    local timestamp
    printf -v timestamp "%(%T)T" -1
    if __is_colorable; then
        printf "\e[38;5;250m%s\e[0m\e[38;5;248m [•] %s\e[0m\n" "${timestamp}" "${1}"
    else
        printf "%s [%-6s] %s\n" "${timestamp}" "DEBUG" "${1}"
    fi
}

function log_info() {
    local timestamp
    printf -v timestamp "%(%T)T" -1
    if __is_colorable; then
        printf "\e[38;5;250m%s\e[0m [•] %s\n" "${timestamp}" "${1}"
    else
        printf "%s [%-6s] %s\n" "${timestamp}" "INFO" "${1}"
    fi
}

function log_success() {
    local timestamp
    printf -v timestamp "%(%T)T" -1
    if __is_colorable; then
        printf "\e[38;5;250m%s\e[0m\e[38;5;83m [•] %s\e[0m\n" "${timestamp}" "${1}"
    else
        printf "%s [%-6s] %s\n" "${timestamp}" "INFO" "${1}"
    fi
}

function log_notice() {
    local timestamp
    printf -v timestamp "%(%T)T" -1
    if __is_colorable; then
        printf "\e[38;5;250m%s\e[0m\e[38;5;81m [•] %s\e[0m\n" "${timestamp}" "${1}"
    else
        printf "%s [%-6s] %s\n" "${timestamp}" "NOTICE" "${1}"
    fi
}

function log_warning() {
    local timestamp
    printf -v timestamp "%(%T)T" -1
    if __is_colorable; then
        printf "\e[38;5;250m%s\e[0m\e[38;5;214m [•] %s\e[0m\n" "${timestamp}" "${1}"
    else
        printf "%s [%-6s] %s\n" "${timestamp}" "WARN" "${1}"
    fi
}

function log_error() {
    local timestamp
    printf -v timestamp "%(%T)T" -1
    if __is_colorable; then
        printf "\e[38;5;250m%s\e[0m\e[38;5;197m [•] %s\e[0m\n" "${timestamp}" "${1}"
    else
        printf "%s [%-6s] %s\n" "${timestamp}" "ERROR" "${1}"
    fi
}

function log_tail() {
    local timestamp

    local colorable="false"
    if __is_colorable; then
        colorable="true"
    fi

    while IFS= read -r line; do
        printf -v timestamp "%(%T)T" -1
        if [[ $colorable == "true" ]]; then
            printf "\e[38;5;250m%s\e[0m\e[38;5;246m [•] (%s) %s\e[0m\n" "${timestamp}" "${1:-unknown}" "${line}"
        else
            printf "%s [%-6s] (%s) %s\n" "${timestamp}" "INFO" "${1:-unknown}" "${line}"
        fi
    done
}

function log_abort() {
    log_error "${1}"
    exit 1
}

function __signal_handler() {
    log_error "User Interrupt! CTRL-C/SIGTERM"
    exit 4
}

function __exit_handler() {
    if [[ ${__GO_BOOTSTRAP_BUILDER_CLEANUP:-false} != "false" ]]; then
        declare -r builder_unit="go-bootstrap-builder.scope"
        if systemctl --user --quiet is-active "${builder_unit}"; then
            log_warning "Stopping existing builder (${builder_unit})"
            if systemctl --user stop "${builder_unit}" 2>&1 | log_tail "clean"; then
                log_info "Successfully stopped existing builder - ${builder_unit}"
            else
                log_error "Failed to stop existing builder - ${builder_unit}"
            fi
        else
            log_debug "Builder is not running - ${builder_unit}"
        fi
    fi
}

function has_command() {
    if command -v "$1" >/dev/null; then
        return 0
    else
        return 1
    fi
}

# Builds a compiler stage previous bootstrap stage.
function build_stage() {
    local go_root
    local go_root_bootstrap
    local go_distpack_expected_sha256
    local go_dist_flags
    local systemd_instance="user"
    local cgo_enabled
    local go_ld_flags

    while [[ ${1} != "" ]]; do
        case ${1} in
        --go-root)
            shift
            go_root="${1}"
            ;;
        --go-root-bootstrap)
            shift
            go_root_bootstrap="${1}"
            ;;
        --distpack-expected-sha256)
            shift
            go_distpack_expected_sha256="${1}"
            ;;
        --systemd-instance)
            shift
            systemd_instance="${1}"
            ;;
        --go-dist-flags)
            shift
            go_dist_flags="${1}"
            ;;
        --go-ld-flags)
            shift
            go_ld_flags="${1}"
            ;;
        --disable-cgo)
            cgo_enabled=0
            ;;
        *)
            log_error "Invalid argument for build_stage $*"
            exit 1
            ;;
        esac
        shift
    done

    local bootstrap_tool
    local go_root_bootstrap_path
    if [[ $go_root_bootstrap == "" ]]; then
        bootstrap_tool="gcc"
    else
        bootstrap_tool="${go_root_bootstrap}"
        go_root_bootstrap_path="${PWD}/sources/${go_root_bootstrap}"
    fi

    log_notice "----------------------------------------------------------"
    log_notice "Build ${go_root} using ${bootstrap_tool}"
    log_notice "----------------------------------------------------------"

    # We use --scope units because github actions runs its jobs and runner
    # under a single system unit and systemd-run --user will behave poorly
    declare -r builder_unit="go-bootstrap-builder.scope"

    # Cleanup any previous builders.
    if systemctl --user --quiet is-active "${builder_unit}"; then
        log_warning "Killing existing builder - ${builder_unit}"
        if systemctl --user kill "${builder_unit}" 2>&1 | log_tail "clean"; then
            log_info "Successfully killed existing builder - ${builder_unit}"
        else
            log_abort "Failed to kill existing builder - ${builder_unit}"
        fi
    fi

    local go_version_line
    local go_version_file="${PWD}/sources/${go_root}/VERSION"
    if [[ -f ${go_version_file} ]]; then
        read -r go_version_line <"${go_version_file:-/dev/null}"
        if [[ -z ${go_version_line} ]]; then
            log_abort "Failed to read version file - ${go_version_file}"
        fi
    else
        log_abort "${go_root} VERSION file ($go_version_file) not found"
    fi

    local systemd_instance_flag="--user"
    if [[ ${systemd_instance} == "system" ]]; then
        systemd_instance_flag="--system"
    fi

    local go_root_path="${PWD}/sources/${go_root}"
    log_info "VERSION          : ${go_version_line}"
    log_info "GOROOT           : ${go_root_path}"
    log_info "GOROOT_BOOTSTRAP : ${go_root_bootstrap_path}"
    log_info "CGO_ENABLED      : ${cgo_enabled}"
    log_info "GO_DISTFLAGS     : ${go_dist_flags}"
    log_info "GO_LDFLAGS       : ${go_ld_flags}"

    if systemd-run \
        --no-ask-password \
        "${systemd_instance_flag}" \
        --collect \
        --scope \
        --unit "go-bootstrap-builder.scope" \
        -p RuntimeMaxSec=15m \
        -E PATH="/usr/bin:/usr/sbin" \
        -E GOROOT="${go_root_path}" \
        -E GOROOT_BOOTSTRAP="${go_root_bootstrap_path}" \
        -E GO_DISTFLAGS="${go_dist_flags}" \
        -E CGO_ENABLED="${cgo_enabled}" \
        -E GO_LDFLAGS="${go_ld_flags}" \
        --working-directory="${go_root_path}/src" \
        bash make.bash 2>&1 | log_tail "${go_root}"; then
        log_success "Successfully built ${go_root} toolchain"
    else
        log_abort "Failed to build ${go_root} toolchain"
    fi

    if [[ -n ${go_distpack_expected_sha256} ]]; then
        log_info "Verify ${go_root} build is reproducible"
        if [[ ! -f "${go_root_path}/pkg/distpack/${go_version_line}.linux-amd64.tar.gz" ]]; then
            log_abort "Build script did not generate distpack archive"
        fi

        local go_distpack_checksum
        local go_distpack_name="${go_version_line}.linux-amd64.tar.gz"
        local go_distpack_path="sources/${go_root}/pkg/distpack/${go_distpack_name}"
        go_distpack_checksum="$(sha256sum "$go_distpack_path")"
        log_info "Expected checksum : ${go_distpack_expected_sha256}"
        log_info "Actual checksum   : ${go_distpack_checksum%% *}"
        if [[ ${go_distpack_expected_sha256} == "${go_distpack_checksum%% *}" ]]; then
            declare -g __GO_BUILD_VERSION="${go_version_line}"
            declare -g __GO_BUILD_DISTPACK_SHA256="${go_distpack_expected_sha256}"
            declare -g __GO_BUILD_DISTPACK_NAME="${go_distpack_name}"
            declare -g __GO_BUILD_DISTPACK_PATH="${go_distpack_path}"
            log_success "${go_root} checksums match with official releases, build is reproducible"
        else
            log_abort "${go_root} checksums DO NOT MATCH with official releases, build is NOT REPRODUCIBLE"
        fi
    else
        log_notice "Skipped reproducibility checks for ${go_root}"
    fi
}

function display_usage() {
    SCRIPT="$(basename "$0")"
    cat <<EOF
Script to bootstrap go toolchain from go 1.4 sources to latest.

This makes use of docker/podman to properly isolate builds and network.

Usage: ${SCRIPT} [OPTIONS]...

Options:
  -h, --help          Display this help message
  --clean             Clean prebuilt files
  --build             Bootstrap the toolchain from go 1.4

Examples:
  ${SCRIPT} --help    Display help

Environment:
  CLICOLOR_FORCE      Set this to NON-ZERO to force colored output.
EOF
}

function main() {
    if [[ $# -lt 1 ]]; then
        log_error "No arguments specified"
        display_usage
        exit 1
    fi

    local build="false"
    local clean="false"
    local cmd_lock=0

    while [[ ${1} != "" ]]; do
        case ${1} in
        -b | --build)
            build=true
            ;;
        -c | --clean)
            clean=true
            ;;
        --github-actions)
            GITHUB_ACTIONS="true"
            ;;
        -h | --help)
            display_usage
            exit 0
            ;;
        *)
            log_error "Invalid argument(s). See usage below."
            display_usage
            exit 1
            ;;
        esac
        shift
    done

    if [[ $clean == "true" ]]; then
        log_notice "----------------------------------------------------------"
        log_notice "Cleaning prebuilt files"
        log_notice "----------------------------------------------------------"
        declare -a clean_list
        clean_list=(
            "sources/go1.4/bin"
            "sources/go1.4/pkg"
            "sources/go1.4/src/runtime/zasm_linux_amd64.h"
            "sources/go1.4/src/runtime/zgoarch_amd64.go"
            "sources/go1.4/src/runtime/zgoos_linux.go"
            "sources/go1.4/src/runtime/zsys_linux_amd64.s"
            "sources/go1.17/bin"
            "sources/go1.17/pkg"
            "sources/go1.20/bin"
            "sources/go1.20/pkg"
            "sources/go1.22/bin"
            "sources/go1.22/pkg"
            "sources/go1.24/bin"
            "sources/go1.24/pkg"
            "dist"
        )

        errs=0
        for i in "${clean_list[@]}"; do
            log_info "Removing - ${i}"
            if ! rm -rf --one-file-system --dir ./"${i}" 2>&1 | log_tail "clean"; then
                log_error "Failed to remove - ${i}"
                ((++errs))
            fi
        done

        if [[ $errs -gt 0 ]]; then
            log_error "Failed to cleanup prebuilt files"
            exit 1
        fi
    fi

    if [[ $build == "true" ]]; then
        local go_arch go_os
        go_arch="$(uname -m)"
        go_os="$(uname -s)"

        if [[ ${go_arch} != "x86_64" || ${go_os} != "Linux" ]]; then
            log_abort "Bootstrap builds are only supported on linux/amd64 (${go_os:-unknown}/${go_arch:-unknown})"
        else
            log_success "Running on supported platform - linux/amd64"
        fi

        # Check if required commands are present.
        declare -a commands=(
            "systemd-run" # systemd
            "gcc"         # build-essentials
            # "unshare"     # util-linux
            # "mount"       # coreutils
        )

        declare -a missing_commands
        for command in "${commands[@]}"; do
            if ! has_command "$command"; then
                ((++errs))
                missing_commands+=("$command")
            fi
        done

        if [[ ${#missing_commands[@]} -gt 0 ]]; then
            log_abort "Following commands are missing - ${missing_commands[*]}"
        fi

        # Check if user namespaces are supported.
        local user_ns

        local systemd_instance="user"
        if [[ $(id -u) == "0" ]]; then
            log_warning "Go Bootstrapping script SHOULD NOT be run as root"
            systemd_instance="system"
        else
            log_info "Using systemd user instance"
        fi

        # Indicate builders may have to be cleaned up.
        declare -g __GO_BOOTSTRAP_BUILDER_CLEANUP="true"

        # We use --scope units because github actions runs its jobs and runner
        # under a single system unit and systemd-run --user will behave poorly
        declare -r builder_unit="go-bootstrap-builder.scope"

        # Clear various settings that would leak into defaults
        # in the toolchain and change the generated binaries.
        unset GOROOT
        unset GOROOT_BOOTSTRAP
        unset GOPROXY
        unset GOVCS
        unset GOTOOLDIR
        unset GOTOOLDIR
        unset CC_FOR_TARGET
        unset CGO_ENABLED
        unset CXX
        unset CXX_FOR_TARGET
        unset GO386
        unset GOAMD64
        unset GOARM
        unset GOBIN
        unset GOEXPERIMENT
        unset GOMIPS64
        unset GOMIPS
        unset GOPATH
        unset GOPPC64
        unset GOROOT_FINAL
        unset GO_EXTLINK_ENABLED
        unset GO_GCFLAGS
        unset GO_LDFLAGS
        unset GO_LDSO
        unset PKG_CONFIG

        # Keey using local toolchain for bootstrapping.
        export GOTOOLCHAIN="local"

        # Build Go 1.4 as static binaries.
        build_stage \
            --systemd-instance "${systemd_instance}" \
            --go-root "go1.4" \
            --go-dist-flags "-s"

        # Using Go 1.4 Build Go 1.17
        build_stage \
            --systemd-instance "${systemd_instance}" \
            --go-root "go1.17" \
            --go-root-bootstrap "go1.4" \
            --disable-cgo \
            --go-ld-flags '-s'

        # Using Go 1.17 Build Go 1.20
        build_stage \
            --systemd-instance "${systemd_instance}" \
            --go-root "go1.20" \
            --go-root-bootstrap "go1.17" \
            --disable-cgo \
            --go-ld-flags '-s'

        # Using Go 1.20 Build Go 1.22 and generate distpack
        build_stage \
            --systemd-instance "${systemd_instance}" \
            --go-root "go1.22" \
            --go-root-bootstrap "go1.20" \
            --distpack-expected-sha256 0fc88d966d33896384fbde56e9a8d80a305dc17a9f48f1832e061724b1719991 \
            --go-dist-flags "-distpack"

        # Using Go 1.22 Build Go 1.24 and generate distpack
        build_stage \
            --systemd-instance "${systemd_instance}" \
            --go-root "go1.24" \
            --go-root-bootstrap "go1.22" \
            --distpack-expected-sha256 3835e217efb30c6ace65fcb98cb8f61da3429bfa9e3f6bb4e5e3297ccfc7d1a4 \
            --go-dist-flags "-distpack"

        if [[ -z ${__GO_BUILD_DISTPACK_PATH} || -z ${__GO_BUILD_DISTPACK_NAME} || -z ${__GO_BUILD_DISTPACK_SHA256} || -z ${__GO_BUILD_VERSION} ]]; then
            log_abort "Build did not set required __GO_BUILD_* global variables"
        fi

        # Copy distpack to /dist and add bootstrap- prefix to filename.
        if [[ ! -e dist ]]; then
            if ! mkdir -p dist 2>&1 | log_tail "mkdir-dist"; then
                log_abort "Failed to create dist directory"
            fi
        fi

        if cp "${__GO_BUILD_DISTPACK_PATH}" "dist/${__GO_BUILD_DISTPACK_NAME}" 2>&1 | log_tail "copy"; then
            log_success "Copied distpack archive to dist/${__GO_BUILD_DISTPACK_NAME}"
        else
            log_abort "Failed to copy distpack archive to dist/${__GO_BUILD_DISTPACK_NAME}"
        fi

        # Generate checksum file.
        log_info "SHA256 checksum is saved to ${__GO_BUILD_DISTPACK_NAME}.sha256"
        if ! printf "%s" "${__GO_BUILD_DISTPACK_SHA256}" >"dist/${__GO_BUILD_DISTPACK_NAME}.sha256"; then
            log_abort "Failed to generate SHA256 checksum file"
        fi

        # Github Actions.
        if [[ ${GITHUB_ACTIONS} == "true" ]]; then
            log_info "Setting github actions outputs"

            log_info "toolchain-version=${__GO_BUILD_VERSION}"
            log_info "toolchain-checksum=${__GO_BUILD_DISTPACK_SHA256}"
            log_info "toolchain-artifact-name=${__GO_BUILD_DISTPACK_NAME}"
            log_info "toolchain-artifact-sha256-name=${__GO_BUILD_DISTPACK_NAME}.sha256"

            if [[ -n ${GITHUB_OUTPUT} ]]; then
                {
                    echo "toolchain-version=${__GO_BUILD_VERSION}"
                    echo "toolchain-checksum=${__GO_BUILD_DISTPACK_SHA256}"
                    echo "toolchain-artifact-name=${__GO_BUILD_DISTPACK_NAME}"
                    echo "toolchain-artifact-sha256-name=${__GO_BUILD_DISTPACK_NAME}.sha256"
                } >>"${GITHUB_OUTPUT}"
            fi
        fi
    fi
}

# Handle Signals
trap __exit_handler EXIT
trap __signal_handler SIGINT SIGTERM

main "$@"
