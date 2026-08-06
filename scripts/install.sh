#!/usr/bin/env bash
set -euo pipefail

# Variables
fname="$(basename "$0")"
installDir='/usr/share/spotube'
desktopFile='/usr/share/applications/spotube.desktop'
appdata='/usr/share/appdata/spotube.appdata.xml'
iconDir='/usr/share/icons/spotube'
icon="${iconDir}/spotube-logo.png"
symlink='/usr/bin/spotube'
repo='KRTirtho/spotube'

# Populated by download_extract_spotube; cleaned up on exit.
temp=''

function cleanup() {
    if [ -n "${temp}" ] && [ -d "${temp}" ]; then
        rm -rf "${temp}"
    fi
}
trap cleanup EXIT

# Root check - From CAAIS (https://codeberg.org/RaptaG/CAAIS), under GPL-3.0
function rootCheck() {
    if [ "${EUID}" -ne 0 ]; then
        echo "Error: Root permissions are required for ${fname} to work."
        echo "Please run './${fname}' for more information."
        exit 1
    fi
}

# Flags
function help() {
    echo "Usage: sudo ./${fname} [flags]"
    echo 'Flags:'
    echo '  -i, --install <version>    Install any Spotube version (if not specified, the latest is installed).'
    echo '  -h, --help                 This help menu'
    echo '  -r, --remove               Removes Spotube from your system'
    exit 0
}

# Checks whether a given command exists or not and returns bool
function command_exists() {
    command -v "$@" >/dev/null 2>&1
}

function latest_version() {
    wget -qO- "https://api.github.com/repos/${repo}/releases/latest" |
        grep -Po '"tag_name": "\K.*?(?=")'
}

function install_deps() {
    local debianDeps='mpv libappindicator3-1 gir1.2-appindicator3-0.1 libsecret-1-0 libnotify-bin libjsoncpp25'
    local rpmDeps='mpv libappindicator jsoncpp libsecret libnotify'
    local archDeps='mpv libappindicator-gtk3 libsecret jsoncpp libnotify'

    if command_exists apt; then
        # shellcheck disable=SC2086
        apt install -y ${debianDeps}
    elif command_exists dnf; then
        # shellcheck disable=SC2086
        dnf install -y ${rpmDeps}
    elif command_exists yum; then
        # shellcheck disable=SC2086
        yum install -y ${rpmDeps}
    elif command_exists zypper; then
        # shellcheck disable=SC2086
        zypper install -y ${rpmDeps}
    elif command_exists pacman; then
        # shellcheck disable=SC2086
        pacman -Sy ${archDeps}
    else
        echo 'You have to install some dependencies manually in order for Spotube to work.'
        echo "The deps are the following: ${rpmDeps}"
    fi
}

# Verifies a downloaded file against the RELEASE.sha256sum published alongside
# it. This only detects corruption and non-TLS tampering: the checksum file
# comes from the same origin as the tarball, so it is not a signature.
function verify_checksum() {
    local file="$1" sumFile="$2" name expected
    name="$(basename "${file}")"

    expected="$(awk -v f="${name}" '$2 == f || $2 == "*"f { print $1; exit }' "${sumFile}")"

    if [ -z "${expected}" ]; then
        echo "Error: no checksum entry for ${name} in RELEASE.sha256sum." >&2
        return 1
    fi

    if ! echo "${expected}  ${file}" | sha256sum -c - >/dev/null 2>&1; then
        echo "Error: checksum verification FAILED for ${name}." >&2
        echo 'The download was corrupted or tampered with. Aborting.' >&2
        return 1
    fi

    echo 'Checksum OK.'
}

function download_extract_spotube() {
    local releaseTag tarName downloadURL sumURL tarPath sumPath

    if [ "${ver}" = 'nightly' ]; then
        releaseTag='nightly'
        tarName='spotube-linux-nightly-x86_64.tar.xz'
    else
        releaseTag="v${ver}"
        tarName="spotube-linux-${ver}-x86_64.tar.xz"
    fi

    downloadURL="https://github.com/${repo}/releases/download/${releaseTag}/${tarName}"
    sumURL="https://github.com/${repo}/releases/download/${releaseTag}/RELEASE.sha256sum"

    # A private mktemp directory rather than a predictable /tmp path. The old
    # fixed path plus a "skip download if the file exists" branch let any local
    # user pre-plant a tarball that this script then installed as root.
    temp="$(mktemp -d "${TMPDIR:-/tmp}/spotube-install.XXXXXXXXXX")"
    chmod 700 "${temp}"

    tarPath="${temp}/${tarName}"
    sumPath="${temp}/RELEASE.sha256sum"

    echo "Downloading ${tarName}..."
    wget -q --https-only -O "${tarPath}" "${downloadURL}"

    echo 'Downloading checksums...'
    wget -q --https-only -O "${sumPath}" "${sumURL}"

    verify_checksum "${tarPath}" "${sumPath}"

    tar -xf "${tarPath}" -C "${temp}" --no-same-owner --no-same-permissions

    if [ -z "$(ls -A "${temp}")" ]; then
        echo 'Failed to extract the tarball. Installation aborted.' >&2
        exit 1
    fi
}

function install_spotube() {
    if [ -d "${installDir}" ]; then
        echo -n 'Spotube is already installed. Do you want to reinstall it? [y/N] '
        read -r reinstall

        case "${reinstall}" in
        [yY]*)
            uninstall_spotube
            ;;
        *)
            echo 'Aborting installation...'
            exit 1
            ;;
        esac
    fi

    mkdir -p "${installDir}" "${iconDir}"
    mv "${temp}/data" "${installDir}"
    mv "${temp}/lib" "${installDir}"
    mv "${temp}/spotube" "${installDir}"
    mv "${temp}/spotube.desktop" "${desktopFile}"
    mv "${temp}/com.github.KRTirtho.Spotube.appdata.xml" "${appdata}"
    mv "${temp}/spotube-logo.png" "${icon}"
    ln -sf "${installDir}/spotube" "${symlink}"

    echo "Spotube ${ver} has been installed successfully!"
}

function uninstall_spotube() {
    echo -n 'Are you sure you want to uninstall Spotube? [y/N] '
    read -r confirm

    case "${confirm}" in
    [yY]*)
        echo 'Uninstalling Spotube..'
        rm -rf "${installDir}" "${desktopFile}" "${appdata}" "${iconDir}" "${symlink}"
        ;;
    *)
        echo 'Aborting...'
        exit 0
        ;;
    esac
}

case "${1:-}" in
-i | --install)
    if [ -n "${2:-}" ]; then
        ver="$2"
    else
        ver="$(latest_version)"
        ver="${ver#v}"
    fi

    if [ -z "${ver}" ]; then
        echo 'Error: could not determine the version to install.' >&2
        exit 1
    fi

    rootCheck
    install_deps
    download_extract_spotube
    install_spotube
    exit 0
    ;;
-r | --remove)
    rootCheck
    uninstall_spotube
    exit 0
    ;;
-h | --help | "")
    help
    exit 0
    ;;
*)
    echo "Invalid flag '$1'"
    echo "Please run ./${fname} for more information."
    exit 1
    ;;
esac
