#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2155
set -o pipefail

function __is_colorable() {
    if [[ -n ${CLICOLOR_FORCE} ]] && [[ ${CLICOLOR_FORCE} != "0" ]]; then
        return 0
    elif [[ -n ${NO_COLOR} ]] || [[ ${CLICOLOR} == "0" ]]; then
        return 1
    fi

    if [[ (-t 1 && (${TERM} != "dumb" && ${TERM} != "linux")) || ${CI} == "true" || ${GITHUB_ACTIONS} == "true" ]]; then
        return 0 # returns 0, i.e true.
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
        printf "\e[38;5;250m%s\e[0m\e[38;5;196m [•] %s\e[0m\n" "${timestamp}" "${1}"
    else
        printf "%s [%-6s] %s\n" "${timestamp}" "ERROR" "${1}"
    fi
}

function log_tail() {
    local colorable="false"
    if __is_colorable; then
        colorable="true"
    fi

    local timestamp
    while IFS= read -r line; do
        printf -v timestamp "%(%T)T" -1
        if [[ $colorable == "true" ]]; then
            printf "\e[38;5;250m%s\e[0m\e[38;5;246m [•] (%s) %s\e[0m\n" "${timestamp}" "${1:-unknown}" "${line}"
        else
            printf "%s [%-6s] (%s) %s\n" "${timestamp}" "INFO" "${1:-unknown}" "${line}"
        fi
    done
}

function log_tail_error() {
    local colorable="false"
    if __is_colorable; then
        colorable="true"
    fi

    local timestamp
    while IFS= read -r line; do
        printf -v timestamp "%(%T)T" -1
        if [[ $colorable == "true" ]]; then
            printf "\e[38;5;250m%s\e[0m\e[38;5;197m [•] (%s) %s\e[0m\n" "${timestamp}" "${1:-unknown}" "${line}"
        else
            printf "%s [%-6s] (%s) %s\n" "${timestamp}" "INFO" "${1:-unknown}" "${line}"
        fi
    done
}

function __log_draw_line() {
    local line
    local level="${1}"
    printf -v line '%.0s-' {1..90}
    case ${level,,} in
    debug)
        log_debug "${line}"
        ;;
    info)
        log_info "${line}"
        ;;
    notice)
        log_notice "${line}"
        ;;
    success)
        log_success "${line}"
        ;;
    warn | warning)
        log_warning "${line}"
        ;;
    error)
        log_error "${line}"
        ;;
    esac
}

function log_draw_line_debug() {
    __log_draw_line "debug"
}

function log_draw_line_info() {
    __log_draw_line "info"
}

function log_draw_line_notice() {
    __log_draw_line "notice"
}

function log_draw_line_success() {
    __log_draw_line "success"
}

function log_draw_line_warning() {
    __log_draw_line "warning"
}

function log_draw_line_error() {
    __log_draw_line "error"
}

function log_abort() {
    log_error "${1}"
    exit 1
}

function __exit_handler() {
    if [[ ${__GO_BOOTSTRAP_BUILDER_CLEANUP:-false} != "false" ]]; then
        declare -r builder_unit="go-bootstrap-task-runner.service"
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

function __signal_handler_sigterm() {
    log_error "Received signal - SIGTERM, Shutting down workers and exiting..."
    exit 4
}

function __signal_handler_sigint() {
    log_error "Received signal - SIGINT, Shutting down workers and exiting..."
    exit 5
}

# Fetches sources pointing at a specific commit.
# This does not overwrite any dirs.
function fetch_sources() {
    local version
    local name
    local commit
    local systemd_instance="user"

    while [[ ${1} != "" ]]; do
        case ${1} in
        --commit)
            shift
            commit="${1}"
            ;;
        --name)
            shift
            name="${1}"
            ;;
        --version)
            shift
            version="${1}"
            ;;
        --systemd)
            shift
            systemd_instance="${1}"
            ;;
        *)
            log_abort "Invalid argument for fetch_sources $*"
            ;;
        esac
        shift
    done

    if [[ -z ${name} || -z ${version} ]]; then
        log_abort "fetch_sources: --name/--version cannot be empty"
    fi

    # Check if name is valid. Allows go1.x format only.
    if [[ ! ${name} =~ ^go1.[0-9][0-9]?$ ]]; then
        log_abort "fetch_sources: invalid name: ${name}"
    fi

    # Check if version is valid.
    if [[ ! ${version} =~ ^go1.((4-bootstrap-[0-9]+)|([0-9]+)(rc[0-9]|.[0-9]+))$ ]]; then
        log_abort "fetch_sources: invalid version: ${version}"
    fi

    # Check if commit hash is valid. Lowercases only.
    if [[ -z ${commit} ]]; then
        log_abort "fetch_sources: commit cannot be empty"
    fi

    if [[ ! ${commit} =~ ^[0-9a-f]{5,40}$ ]]; then
        log_abort "fetch_sources: invalid commit hash: ${commit}"
    fi

    local systemd_instance_flag="--user"
    if [[ ${systemd_instance} == "system" ]]; then
        systemd_instance_flag="--system"
    fi

    log_notice "Fetch ${name}@${commit}"
    log_draw_line_notice

    # Check if directory already exists. If exits, commit hash is expected one.
    local __output_dir="upstream/${name}"
    if [[ -e ${__output_dir} ]]; then
        log_debug "Directory already exists: ${__output_dir}"
        # Verify we already have the correct source.
        local existing_commit
        existing_commit="$(git --no-pager --git-dir="${__output_dir}/.git" show --quiet --format=%H HEAD 2> >(log_tail_error "git" 1>&2))"
        if [[ -z ${existing_commit} ]]; then
            log_abort "Failed to get existing commit hash for ${name}"
        fi

        if [[ ${existing_commit,,} == "${commit}" ]]; then
            log_success "Expected commit hash: ${commit}"
            log_success "Actual commit hash  : ${existing_commit}"
        else
            log_error "Commit hash mismatch for ${name}"
            log_error "Expected commit hash: ${commit}"
            log_abort "Actual commit hash  : ${existing_commit}"
        fi
    else
        log_info "Downloading ${name} sources to ${__output_dir}"

        # Cleanup any previous workers.
        declare -r builder_unit="go-bootstrap-task-runner.service"
        if systemctl --user --quiet is-active "${builder_unit}"; then
            log_warning "Stopping existing worker - ${builder_unit}"
            if systemctl --user stop "${builder_unit}" 2>&1 | log_tail "clean"; then
                log_info "Successfully killed existing worker - ${builder_unit}"
            else
                log_abort "Failed to stop existing worker - ${builder_unit}"
            fi
        fi

        # Inherit the slice when not running in CI.
        declare -a systemd_run_options=("--collect" "--wait" "--pipe" "--same-dir")
        if [[ $CI != "true" && $GITHUB_ACTIONS != "true" ]]; then
            systemd_run_options+=("--slice-inherit")
        fi

        if systemd-run \
            --quiet \
            --no-ask-password \
            "${systemd_instance_flag}" \
            "${systemd_run_options[@]}" \
            --unit "${builder_unit}" \
            -p RuntimeMaxSec=15m \
            -E TERM=dumb \
            git clone \
            --quiet \
            -c advice.detachedHead=false \
            --depth=1 \
            --revision "${commit}" \
            https://go.googlesource.com/go \
            "${__output_dir}" 2>&1 | log_tail "${name}"; then
            log_success "Downloaded sources for ${name} to ${__output_dir}"
        else
            log_abort "Failed to download sources for ${name} to ${__output_dir}"
        fi
    fi

    local go_version_line
    local go_version_file="${__output_dir}/VERSION"
    if [[ -f ${go_version_file} ]]; then
        read -r go_version_line <"${go_version_file:-/dev/null}"
        if [[ -z ${go_version_line} ]]; then
            log_abort "Failed to read version file - ${go_version_file}"
        fi
    else
        log_abort "${name} VERSION file ($go_version_file) not found"
    fi

    # Ensure that name matches the version.
    if [[ ${go_version_line} != "${version}" ]]; then
        log_error "Expected VERSION    : ${version}"
        log_abort "Actual VERSION      : ${go_version_line}"
    else
        log_success "Expected VERSION    : ${version}"
        log_success "Actual VERSION      : ${go_version_line}"
        log_draw_line_success
    fi
}

# Builds a compiler stage using previous stage or gcc.
function build_stage() {
    local go_root
    local go_root_bootstrap
    local version
    local name
    local systemd_instance="user"
    local go_distpack_toolchain_sha256
    local dry_build

    while [[ ${1} != "" ]]; do
        case ${1} in
        --name)
            shift
            name="${1}"
            ;;
        --version)
            shift
            version="${1}"
            ;;
        --bootstrap)
            shift
            go_root_bootstrap="${1}"
            ;;
        --expect)
            shift
            go_distpack_toolchain_sha256="${1}"
            ;;
        --systemd)
            shift
            systemd_instance="${1}"
            ;;
        --dry-build)
            shift
            dry_build="${1}"
            ;;
        *)
            log_abort "build_stage: Invalid arguments - $*"
            ;;
        esac
        shift
    done

    # Configure bootstrap toolchain.
    local bootstrap_tool
    local go_root_bootstrap_path
    if [[ -z $go_root_bootstrap || $go_root_bootstrap == "gcc" ]]; then
        bootstrap_tool="gcc"
    else
        bootstrap_tool="${go_root_bootstrap}"
        go_root_bootstrap_path="${PWD}/upstream/${go_root_bootstrap}"
    fi

    # If build is not reproducible, then build a static binary,
    # with cgo disabled. It does not matter for later stages.
    local go_dist_flags="-distpack"
    local cgo_enabled
    local go_ld_flags
    if [[ ${go_distpack_toolchain_sha256} == "null" || ${go_distpack_toolchain_sha256} == "none" ]]; then
        cgo_enabled=0
        go_ld_flags="-s"
        go_dist_flags=""
        go_distpack_toolchain_sha256="none"
    fi

    log_notice "Build ${name} using ${bootstrap_tool}"
    log_draw_line_notice

    # systemd ephemeral unit which runs the the actual build task.
    declare -r builder_unit="go-bootstrap-task-runner.service"

    # Cleanup any previous builders.
    if systemctl --user --quiet is-active "${builder_unit}"; then
        log_warning "Stopping existing builder - ${builder_unit}"
        if systemctl --user stop "${builder_unit}" 2>&1 | log_tail "clean"; then
            log_info "Successfully killed existing builder - ${builder_unit}"
        else
            log_abort "Failed to stop existing builder - ${builder_unit}"
        fi
    fi

    local go_version_line
    local go_version_file="upstream/${name}/VERSION"
    if [[ -f ${go_version_file} ]]; then
        read -r go_version_line <"${go_version_file:-/dev/null}"
        if [[ -z ${go_version_line} ]]; then
            log_abort "Failed to read version file - ${go_version_file}"
        fi
    else
        log_abort "${name} VERSION file ($go_version_file) not found"
    fi

    # Ensure that name matches the version.
    if [[ ${go_version_line} != "${version}" ]]; then
        log_abort "Go version in VERSION file(${go_version_line}) MUST match version(${version})"
    fi

    # Vast majority of the builds are done as normal user.
    local systemd_instance_flag="--user"
    if [[ ${systemd_instance} == "system" ]]; then
        systemd_instance_flag="--system"
    fi

    local go_root_path
    go_root_path="${PWD}/upstream/${name}"

    log_info "VERSION          : ${go_version_line}"
    log_info "GOROOT           : ${go_root_path}"
    log_info "GOROOT_BOOTSTRAP : ${go_root_bootstrap_path}"
    log_info "CGO_ENABLED      : ${cgo_enabled}"
    log_info "GO_DISTFLAGS     : ${go_dist_flags}"
    log_info "GO_LDFLAGS       : ${go_ld_flags}"

    # Inherit the slice when not running in CI.
    declare -a systemd_run_options=("--collect" "--wait" "--pipe" "--same-dir")
    if [[ $CI != "true" && $GITHUB_ACTIONS != "true" ]]; then
        systemd_run_options+=("--slice-inherit")
    fi

    # Clear various settings that would leak into defaults
    # in the toolchain and change the generated binaries.
    if [[ ${dry_build} == "false" ]]; then
        if systemd-run \
            --quiet \
            --send-sighup \
            --no-ask-password \
            "${systemd_instance_flag}" \
            "${systemd_run_options[@]}" \
            --unit "${builder_unit}" \
            -p RuntimeMaxSec=15m \
            -E GOROOT="${go_root_path}" \
            -E GOROOT_BOOTSTRAP="${go_root_bootstrap_path}" \
            -E GO_DISTFLAGS="${go_dist_flags}" \
            -E CGO_ENABLED="${cgo_enabled}" \
            -E GO_LDFLAGS="${go_ld_flags}" \
            -E GOTOOLCHAIN="local" \
            -E GOPROXY="" \
            -E GOVCS="" \
            -E GOTOOLDIR="" \
            -E GOTOOLDIR="" \
            -E CC_FOR_TARGET="" \
            -E CXX="" \
            -E CXX_FOR_TARGET="" \
            -E GO386="" \
            -E GOAMD64="" \
            -E GOARM="" \
            -E GOBIN="" \
            -E GOEXPERIMENT="" \
            -E GOMIPS64="" \
            -E GOMIPS="" \
            -E GOPATH="" \
            -E GOPPC64="" \
            -E GOROOT_FINAL="" \
            -E GO_EXTLINK_ENABLED="" \
            -E GO_GCFLAGS="" \
            -E GO_LDSO="" \
            -E PKG_CONFIG="" \
            --working-directory="${go_root_path}/src" \
            bash make.bash 2>&1 | log_tail "${name}"; then
            log_success "Successfully built ${name} toolchain"
            log_draw_line_success
        else
            log_abort "Failed to build ${name} toolchain"
        fi
    else
        log_warning "Skipped building ${name}, as --dry-build is enabled"
    fi

    if [[ ${go_distpack_toolchain_sha256} != "none" && ${dry_build} != "true" ]]; then
        log_info "Verifying ${name} build is reproducible"
        log_draw_line_info
        if [[ ! -f "${go_root_path}/pkg/distpack/${go_version_line}.linux-amd64.tar.gz" ]]; then
            log_abort "Build script did not generate distpack archive"
        fi

        local go_distpack_toolchain_checksum
        local go_distpack_toolchain_name="${go_version_line}.linux-amd64.tar.gz"
        local go_distpack_toolchain_path="upstream/${name}/pkg/distpack/${go_distpack_toolchain_name}"
        go_distpack_toolchain_checksum="$(sha256sum "$go_distpack_toolchain_path")"

        if [[ ${go_distpack_toolchain_sha256} == "${go_distpack_toolchain_checksum%% *}" ]]; then
            declare -g __GO_BUILD_VERSION="${go_version_line}"
            declare -g __GO_DISTPACK_TOOLCHAIN_SHA256="${go_distpack_toolchain_sha256}"
            declare -g __GO_DISTPACK_TOOLCHAIN_NAME="${go_distpack_toolchain_name}"
            declare -g __GO_DISTPACK_TOOLCHAIN_PATH="${go_distpack_toolchain_path}"

            log_success "Expected checksum : ${go_distpack_toolchain_sha256}"
            log_success "Actual checksum   : ${go_distpack_toolchain_checksum%% *}"
            log_success "${name} checksums match with official releases, build is reproducible"
            log_draw_line_success
        else
            log_error "Expected checksum : ${go_distpack_toolchain_sha256}"
            log_error "Actual checksum   : ${go_distpack_toolchain_checksum%% *}"
            log_abort "${name} checksums DO NOT MATCH with official releases, build is NOT REPRODUCIBLE"
        fi
    else
        log_warning "Skipped reproducibility checks for ${name}"
        log_draw_line_warning
    fi
}

function display_usage() {
    local script
    script="$(basename "$0")"

    cat <<EOF
         ▌        ▐     ▐
▞▀▌▞▀▖▄▄▖▛▀▖▞▀▖▞▀▖▜▀ ▞▀▘▜▀ ▙▀▖▝▀▖▛▀▖
▚▄▌▌ ▌   ▌ ▌▌ ▌▌ ▌▐ ▖▝▀▖▐ ▖▌  ▞▀▌▙▄▘
▗▄▘▝▀    ▀▀ ▝▀ ▝▀  ▀ ▀▀  ▀ ▘  ▝▀▘▌

Script to bootstrap go toolchain from go1.4 sources.

Usage: ${script} [OPTIONS]...

Options:
  --build             Bootstrap the go toolchain
  --clean             Clean build artifacts
  --clean-all         Clean sources and build artifacts
  -h, --help          Display this help message

Environment:
  CLICOLOR_FORCE      Set this to NON-ZERO to force colored output.
EOF
}

function main() {
    if [[ $# -lt 1 ]]; then
        log_error "Please specify an action like --build/--clean"
        log_abort "See $(basename "$0") --help for more info"
    fi

    local build="false"
    local clean="false"
    local fetch="false"
    local dry_build="false"

    local go_stage_0="gcc"
    local build_from=""

    while [[ ${1} != "" ]]; do
        case ${1} in
        -b | --build)
            build=true
            fetch="true"
            ;;
        -c | --clean)
            clean=true
            ;;
        --from-stage)
            shift
            build_from="${1}"
            ;;
        --fetch)
            fetch="true"
            ;;
        --github-actions | --actions)
            GITHUB_ACTIONS="true"
            ;;
        --dry-build)
            dry_build="true"
            build="true"
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

    # Running the script without any flags does nothing, but print some help message.
    if [[ $clean == "false" && $build == "false" && $fetch == "false" ]]; then
        log_abort "Invalid Flags: Please specify an action like --build/--clean/--fetch"
    fi

    # Ensure that script is running from repository root as working directory.
    if [[ ! -s go-bootstrap.sh ]] || [[ ! -s go-bootstrap.json ]]; then
        log_abort "This script MUST be executed from repository root!"
    fi

    if [[ $clean == "true" ]]; then
        log_draw_line_notice
        log_notice "Cleaning sources and build artifacts"
        log_draw_line_notice
        log_info "Removing - upstream/*"
        if ! rm -rf --one-file-system --dir upstream 2>&1 | log_tail "clean-all"; then
            log_abort "Failed to remove - upstream/"
        fi

        log_info "Removing - dist/*"
        if ! rm -rf --one-file-system --dir dist 2>&1 | log_tail "clean-all"; then
            log_abort "Failed to remove - dist/"
        fi
    fi

    if [[ $build == "true" || $fetch == "true" ]]; then
        local go_arch go_os
        go_arch="$(uname -m)"
        go_os="$(uname -s)"

        if [[ ${go_arch,,} != "x86_64" || ${go_os,,} != "linux" ]]; then
            log_abort "Bootstrap builds are only supported on linux/amd64 (${go_os:-unknown}/${go_arch:-unknown})"
        fi

        # Check if required commands are present.
        declare -a commands=(
            "systemd-run" # systemd
            "sha256sum"   # coreutils
            "gcc"         # gcc
            "git"         # git
            "jq"          # jq
        )

        declare -a missing_commands
        for command in "${commands[@]}"; do
            if ! command -v "$command" >/dev/null; then
                ((++errs))
                missing_commands+=("$command")
            fi
        done

        if [[ ${#missing_commands[@]} -gt 0 ]]; then
            log_abort "Following commands are missing - ${missing_commands[*]}"
        fi

        local systemd_instance="user"
        if [[ $(id -u) == "0" ]]; then
            log_warning "Go Bootstrapping script SHOULD NOT be run as root"
            systemd_instance="system"
        else
            log_info "Using systemd user instance"
        fi

        # Get script's path.
        log_draw_line_notice
        log_notice "Parsing and validating bootstrap configuration"
        log_draw_line_notice

        local script_dir
        local config_path
        script_dir="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
        config_path="${script_dir}/go-bootstrap.json"
        log_info "Script Directory: ${script_dir}"
        log_info "Config Path     : ${config_path}"

        # Check if config file exits.
        if [[ ! -f ${config_path} ]]; then
            log_abort "Missing build configuration: ${config_path}"
        fi

        # Read configuration file and parse it.
        local config_data
        log_info "Parsing configuration file ${config_path}"
        config_data="$(<"${config_path}")"

        # Dump config file
        log_tail "config" <<<"${config_data}"

        # Each element of the array MUST have name, commit, version and checksum keys.
        if jq --exit-status '.steps | map(
                (has("name") and (.name | type == "string")) and
                (has("version") and (.version | type == "string")) and
                (has("commit") and (.commit | type == "string")) and
                (has("checksum") and (.checksum | type == "string" or .checksum == null))
            ) | all' <<<"$config_data" 2>&1 >/dev/null | log_tail_error "validate"; then
            log_success "Config file is a valid JSON, with required fields"
        else
            log_error "Config file ${config_path} is invalid!"
            log_abort "Please ensure that config file is a valid JSON, with required fields"
        fi

        # Now that config is a valid JSON with required fields,
        # ensure that values are valid and acceptable.
        log_notice "Validating config data from JSON"
        declare -a steps
        declare -A bootstrap_map
        declare -A version_map
        declare -A commit_map
        declare -A repro_map

        # Read all the names in the steps. Oder of steps matters!!
        readarray -t steps < <(jq -r '.steps[].name' <<<"${config_data}" 2>/dev/null)
        if [[ ${#steps[@]} -lt 4 ]]; then
            log_abort "Config defines only ${#steps[@]} steps, minimum 4 required"
        fi

        # Build config maps.
        # name->version,
        # name->bootstrap,
        # name->commit,
        # name->reproducible hash.
        declare -i config_errors=0
        log_draw_line_debug
        for index in "${!steps[@]}"; do
            local item="${steps[${index}]}"

            # Validate all the steps have a valid name.
            if [[ ! ${item} =~ ^go1.[0-9] ]]; then
                log_error "Name ${item} is not a valid go version."
                ((++config_errors))
                continue
            else
                log_debug "Toolchain Name        : ${item}"
            fi

            # Build bootstrap map from names.
            # Bootstrap must start from go1.4 (which uses gcc/clang).
            if [[ ${index} -eq 0 ]]; then
                if [[ ! ${item} =~ ^go1.4$ ]]; then
                    log_error "First toolchain to be build MUST be go1.4, but got ${item}"
                    ((++config_errors))
                    continue
                fi
                bootstrap_map["${item}"]="gcc"
            else
                bootstrap_map["${item}"]="${steps[${index} - 1]}"
            fi
            log_debug "Bootstrap Toolchain   : ${bootstrap_map["${item}"]}"

            # Build version map from names.
            local __version
            __version="$(jq -r --arg name "${item}" '.steps[] | select(.name==$name) | .version' <<<"${config_data}" 2>/dev/null)"
            if [[ ! ${__version} =~ ^go1.((4-bootstrap-[0-9]+)|([0-9]+)(rc[0-9]|.[0-9]+))$ ]]; then
                log_error "Version for ${item} is not valid!"
                ((++config_errors))
                continue
            else
                log_debug "Release Version       : ${__version}"
                version_map["${item}"]="${__version,,}"
            fi
            unset __version

            # Build commit map from names.
            local __commit
            __commit="$(jq -r --arg name "${item}" '.steps[] | select(.name==$name) | .commit' <<<"${config_data}" 2>/dev/null)"
            if [[ ! ${__commit} =~ ^[a-fA-F0-9]{40}$ ]]; then
                log_error "Commit for building ${item}(${__commit}) is not a valid SHA1 hash"
                ((++config_errors))
                continue
            else
                log_debug "Upstream Commit       : ${__commit}"
                commit_map["${item}"]="${__commit,,}"
            fi
            unset __commit

            # Build reproducible hash map from names.
            local __repro
            __repro="$(jq -r --arg name "${item}" '.steps[] | select(.name==$name) | .checksum' <<<"${config_data}" 2>/dev/null)"
            if [[ -z ${__repro} || ${__repro} == "null" ]]; then
                local __go_major_version="${item#go1.}"
                __go_major_version="${__go_major_version%%.*}"
                __go_major_version="${__go_major_version%%-*}"
                # Ensure that go versions > go1.21 are always reproducible.
                if [[ $__go_major_version  -gt 21 ]]; then
                    log_error "${item} is guaranteed to be reproducible, but SHA256 hashes are missing"
                    ((++config_errors))
                else
                    log_debug "Reproducible Hash     : not supported, skipped"
                    repro_map["${item}"]="null"
                fi
            elif [[ ! ${__repro} =~ ^[a-fA-F0-9]{64}$ ]]; then
                log_error "Expected artifact hash for ${item}(${__repro}) is not a valid SHA256"
                ((++config_errors))
                continue
            else
                log_debug "Reproducible Hash     : ${__repro}"
                repro_map["${item}"]="${__repro,,}"
            fi
            unset __repro
            log_draw_line_debug
        done

        # Abort, if config has errors.
        if [[ ${config_errors} -gt 0 ]]; then
            log_abort "Bootstrap configuration has ${config_errors} error(s), please fix them to continue"
        fi

        # Check if from is valid go version already specified.
        declare -u step_init_index=0
        if [[ -n ${build_from} ]]; then
            if [[ ! " ${steps[*]} " =~ [[:space:]]${build_from}[[:space:]] ]]; then
                log_abort "--from specifies a toolchain which is not defined in the config"
            fi
        fi

        for build_from_index in "${!steps[@]}"; do
            if [[ ${steps["${build_from_index}"]} == "${build_from}" ]]; then
                step_init_index="${build_from_index}"
            fi
        done
        log_debug "Build will start from index ${step_init_index}(${steps["${step_init_index}"]})"
        log_draw_line_debug

        # Indicate builders may have to be cleaned up.
        declare -g __GO_BOOTSTRAP_BUILDER_CLEANUP="true"
    fi

    # Fetch sources step by step. Abort if any stage errors.
    if [[ $fetch == "true" ]]; then
        declare -i step_index=0
        for step in "${steps[@]}"; do
            fetch_sources \
                --name "${step}" \
                --systemd "${systemd_instance}" \
                --version "${version_map["${step}"]}" \
                --commit "${commit_map["${step}"]}"
        done
    fi

    # Build step by step. Abort if any stage errors.
    if [[ $build == "true" ]]; then
        declare -i step_index=0
        for step in "${steps[@]}"; do
            if [[ ${step_index} -lt ${step_init_index} ]]; then
                log_warning "Skipped building ${step}"
                log_draw_line_warning
                ((step_index++))
                continue
            fi
            build_stage \
                --name "${step}" \
                --systemd "${systemd_instance}" \
                --bootstrap "${bootstrap_map["${step}"]}" \
                --version "${version_map["${step}"]}" \
                --expect "${repro_map["${step}"]}" \
                --dry-build "${dry_build}"
            ((step_index++))
        done

        if [[ -z ${__GO_DISTPACK_TOOLCHAIN_PATH} || -z ${__GO_DISTPACK_TOOLCHAIN_NAME} || -z ${__GO_DISTPACK_TOOLCHAIN_SHA256} || -z ${__GO_BUILD_VERSION} ]]; then
            log_abort "Build did not set required __GO_BUILD_* global variables"
        fi

        # Copy distpack to /dist.
        if [[ ! -e dist ]]; then
            if ! mkdir -p dist 2>&1 | log_tail "mkdir-dist"; then
                log_abort "Failed to create dist directory"
            fi
        fi

        # Copy toolchain to dist/
        if cp "${__GO_DISTPACK_TOOLCHAIN_PATH}" "dist/${__GO_DISTPACK_TOOLCHAIN_NAME}" 2>&1 | log_tail "copy"; then
            log_success "Copied distpack sdk to dist/${__GO_DISTPACK_TOOLCHAIN_NAME}"
        else
            log_abort "Failed to copy distpack sdk to dist/${__GO_DISTPACK_TOOLCHAIN_NAME}"
        fi

        # Generate Toolchain checksum, This is here to keep it compatibile with go.dev/dl.
        log_info "Toolchain checksum is saved to dist/${__GO_DISTPACK_TOOLCHAIN_NAME}.sha256"
        if ! printf "%s" "${__GO_DISTPACK_TOOLCHAIN_SHA256}" \
            >"dist/${__GO_DISTPACK_TOOLCHAIN_NAME}.sha256"; then
            log_abort "Failed to generate SHA256 checksum file"
        fi

        # Github Actions.
        if [[ ${GITHUB_ACTIONS} == "true" ]]; then
            log_info "toolchain-version=${__GO_BUILD_VERSION}"
            log_info "toolchain-checksum=${__GO_DISTPACK_TOOLCHAIN_SHA256}"
            log_info "toolchain-filename=${__GO_DISTPACK_TOOLCHAIN_NAME}"
            if [[ -n ${GITHUB_OUTPUT} ]]; then
                {
                    echo "toolchain-version=${__GO_BUILD_VERSION}"
                    echo "toolchain-checksum=${__GO_DISTPACK_TOOLCHAIN_SHA256}"
                    echo "toolchain-filename=${__GO_DISTPACK_TOOLCHAIN_NAME}"

                } >>"${GITHUB_OUTPUT}"
            fi
        fi
    fi
}

# Handle Signals and cleanup workers.
trap __exit_handler EXIT
trap __signal_handler_sigint SIGTERM
trap __signal_handler_sigterm SIGINT

main "$@"
