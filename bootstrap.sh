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
            log_warning "Killing existing builder (${builder_unit})"
            if systemctl --user kill "${builder_unit}" 2>&1 | log_tail "clean"; then
                log_info "Successfully killed existing builder - ${builder_unit}"
            else
                log_error "Failed to kill existing builder - ${builder_unit}"
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

    # https://go.dev/dl
    local bootstrap_dist_expected_sha="0fc88d966d33896384fbde56e9a8d80a305dc17a9f48f1832e061724b1719991"

    if [[ $(id -u) == "0" && ${GITHUB_ACTIONS} != "true" ]]; then
        log_abort "Go Bootstrapping script MUST NOT be run as root"
    fi

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

        if ! has_command "gcc"; then
            log_abort "Missing command gcc"
        fi

        # Avoid checking for systemctl as it may be stubbed.
        if ! has_command "systemd-run"; then
            log_abort "Missing command systemd-run"
        fi

        # Indicate builders may have to be cleaned up.
        declare -g __GO_BOOTSTRAP_BUILDER_CLEANUP="true"
        declare -r __GO_BUILDER_ROOT="$(pwd)"

        # We use --scope units because github actions runs its jobs and runner
        # under a single system unit and systemd-run --user will behave poorly
        declare -r builder_unit="go-bootstrap-builder.scope"

        # Cleanup any leftover builders.
        if systemctl --user --quiet is-active "${builder_unit}"; then
            log_warning "Killing existing builder - ${builder_unit}"
            if systemctl --user kill "${builder_unit}" 2>&1 | log_tail "clean"; then
                log_info "Successfully killed existing builder - ${builder_unit}"
            else
                log_abort "Failed to kill existing builder - ${builder_unit}"
            fi
        fi

        # Build go1.4
        log_notice "----------------------------------------------------------"
        log_notice "Build Go 1.4 using gcc"
        log_notice "----------------------------------------------------------"
        if systemd-run \
            --no-ask-password \
            --user \
            --collect \
            --scope \
            --unit "go-bootstrap-builder.scope" \
            -p RuntimeMaxSec=15m \
            -E PATH="/usr/bin:/usr/sbin" \
            -E GOROOT="${PWD}/sources/go1.4" \
            -E GOROOT_BOOTSTRAP="" \
            --working-directory="${PWD}/sources/go1.4/src" \
            bash make.bash 2>&1 | log_tail "go1.4"; then
            log_success "Successfully built Go 1.4 toolchain"
        else
            log_abort "Failed to build Go 1.4 toolchain"
        fi

        log_notice "----------------------------------------------------------"
        log_notice "Build Go 1.17 using go1.4 as bootstrap toolchain"
        log_notice "----------------------------------------------------------"
        if systemd-run \
            --no-ask-password \
            --user \
            --collect \
            --scope \
            --unit "go-bootstrap-builder.scope" \
            -p RuntimeMaxSec=15m \
            -E PATH="/usr/bin:/usr/sbin" \
            -E GOROOT="${PWD}/sources/go1.17" \
            -E GOROOT_BOOTSTRAP="${PWD}/sources/go1.4" \
            --working-directory="${PWD}/sources/go1.17/src" \
            bash make.bash 2>&1 | log_tail "go1.17"; then
            log_success "Successfully built Go 1.17 toolchain"
        else
            log_abort "Failed to build Go 1.17 toolchain"
        fi

        log_notice "----------------------------------------------------------"
        log_notice "Build Go 1.20 using go1.17 as bootstrap toolchain"
        log_notice "----------------------------------------------------------"
        if systemd-run \
            --no-ask-password \
            --user \
            --collect \
            --scope \
            --unit "go-bootstrap-builder.scope" \
            -p RuntimeMaxSec=15m \
            -E PATH="/usr/bin:/usr/sbin" \
            -E GOROOT="${PWD}/sources/go1.20" \
            -E GOROOT_BOOTSTRAP="${PWD}/sources/go1.17" \
            --working-directory="${PWD}/sources/go1.20/src" \
            bash make.bash 2>&1 | log_tail "go1.20"; then
            log_success "Successfully built Go 1.20 toolchain"
        else
            log_abort "Failed to build Go 1.20 toolchain"
        fi

        # Go 1.21 and later are perfectly reproducible.
        log_notice "----------------------------------------------------------"
        log_notice "Build Go 1.22 using go1.20 as bootstrap toolchain"
        log_notice "----------------------------------------------------------"
        if systemd-run \
            --no-ask-password \
            --user \
            --collect \
            --scope \
            --unit "go-bootstrap-builder.scope" \
            -p RuntimeMaxSec=15m \
            -E PATH="/usr/bin:/usr/sbin" \
            -E GOROOT="${PWD}/sources/go1.22" \
            -E GOROOT_BOOTSTRAP="${PWD}/sources/go1.20" \
            --working-directory="${PWD}/sources/go1.22/src" \
            bash make.bash -distpack 2>&1 | log_tail "go1.22"; then
            log_success "Successfully built Go 1.22 toolchain"
        else
            log_abort "Failed to build Go 1.22 toolchain"
        fi

        log_info "Check Go VERSION file"
        local version_line
        read -r version_line <sources/go1.22/VERSION
        if [[ -z ${version_line} ]]; then
            log_abort "Failed to read version file - sources/go1.22/VERSION"
        else
            log_notice "Go Version - ${version_line}"
        fi

        log_info "Verify build reproducibility "
        if [[ ! -f "sources/go1.22/pkg/distpack/${version_line}.linux-amd64.tar.gz" ]]; then
            log_abort "Build script did not generate distpack archive"
        fi

        local go_bootstrap_checksum
        go_bootstrap_checksum="$(sha256sum "sources/go1.22/pkg/distpack/${version_line}.linux-amd64.tar.gz")"
        log_info "Expected checksum : ${bootstrap_dist_expected_sha}"
        log_info "Actual checksum   : ${go_bootstrap_checksum%% *}"
        if [[ ${bootstrap_dist_expected_sha} == "${go_bootstrap_checksum%% *}" ]]; then
            log_success "Checksums match with official releases, build is reproducible"
        else
            log_abort "Checksum DO NOT MATCH with official releases, build is NOT REPRODUCIBLE"
        fi

        # Copy distpack to /dist and add bootstrap- prefix to filename.
        if [[ ! -e dist ]]; then
            if ! mkdir -p dist 2>&1 | log_tail "mkdir-dist"; then
                log_abort "Failed to create dist directory"
            fi
        fi

        local distpack_artifact_name="bootstrap-${version_line}-linux-amd64.tar.gz"
        if cp \
            "sources/go1.22/pkg/distpack/${version_line}.linux-amd64.tar.gz" \
            "dist/${distpack_artifact_name}" 2>&1 | log_tail "copy"; then
            log_success "Copied distpack archive to dist/${distpack_artifact_name}"
        else
            log_abort "Failed to copy distpack archive to dist/${distpack_artifact_name}"
        fi

        # Generate checksum file.
        log_info "SHA256 checksum is saved to ${distpack_artifact_name}.sha256"
        if ! printf "%s" "${bootstrap_dist_expected_sha}" >"dist/${distpack_artifact_name}.sha256"; then
            log_abort "Failed to generate SHA256 checksum file"
        fi

        # Github Actions.
        if [[ ${GITHUB_ACTIONS} == "true" ]]; then
            log_info "Setting github actions outputs"

            local base64_subjects
            base64_subjects="$(printf "%s  %s" "${bootstrap_dist_expected_sha}" "${distpack_artifact_name}" | base64 -w 0)"

            log_info "toolchain-version=${version_line}"
            log_info "toolchain-checksum=${bootstrap_dist_expected_sha}"
            log_info "toolchain-artifact-name=${distpack_artifact_name}"
            log_info "toolchain-artifact-sha256-name=${distpack_artifact_name}.sha256"

            if [[ -n ${GITHUB_OUTPUT} ]]; then
                {
                    echo "toolchain-version=${version_line}"
                    echo "toolchain-checksum=${bootstrap_dist_expected_sha}"
                    echo "toolchain-artifact-name=${distpack_artifact_name}"
                    echo "toolchain-artifact-sha256-name=${distpack_artifact_name}.sha256"
                } >>"${GITHUB_OUTPUT}"
            fi
        fi
    fi
}

# Handle Signals
trap __exit_handler EXIT
trap __signal_handler SIGINT SIGTERM

main "$@"
