#!/usr/bin/env bash
# 32-bit NVIDIA libraries for aurora-max-nvidia.
#
# aurora-dx-nvidia-open installs the driver with MULTILIB=0
# (ublue-os/aurora build_scripts/base/04-nvidia.sh): no i686 NVIDIA libraries,
# because Aurora's Steam is a Flatpak that brings its own. A native Steam and
# Wine need them on the host, or 32-bit OpenGL/Vulkan programs cannot use the
# NVIDIA GPU.
#
# They come from the same place as Aurora's own driver: Universal Blue's akmods
# image for this kernel, whose /rpms/nvidia/ holds the driver RPMs for both
# arches (ublue-os/akmods build_files/nvidia/download-nvidia-rpms.sh), so the
# versions match the installed x86_64 packages and the kernel module by
# construction. negativo17's repo, where these RPMs originate, only keeps the
# last two releases and drops the one Aurora shipped within days -- the first
# version of this script pinned to it and failed on 2026-10-03.
#
# Any version mismatch fails the build: never a broken image.
set -euo pipefail

fedora=$(rpm -E %fedora)
kernel=$(rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' | head -n1)
# Aurora's :stable builds from the coreos-stable akmods flavour (`akmods_flavor`
# in ublue-os/aurora's Justfile); its other streams use main.
image="ghcr.io/ublue-os/akmods-nvidia-open:coreos-stable-$fedora-$kernel"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for tool in skopeo jq; do
    command -v "$tool" >/dev/null || dnf5 -y install "$tool"
done

echo "fetching $image"
skopeo copy --retry-times 3 "docker://$image" "dir:$work/image"
mkdir "$work/root"
for layer in $(jq -r '.layers[].digest | sub("^sha256:"; "")' "$work/image/manifest.json"); do
    tar -xf "$work/image/$layer" -C "$work/root" --wildcards '*.i686.rpm' 2>/dev/null || true
done
mapfile -t rpms < <(find "$work/root" -name '*.i686.rpm' | sort)
if ((${#rpms[@]} == 0)); then
    echo "no i686 RPMs in $image; did its layout change?" >&2
    exit 1
fi

# Only twins of packages Aurora actually installed.
want=()
for rpm in "${rpms[@]}"; do
    name=$(rpm -qp --queryformat '%{NAME}' "$rpm" 2>/dev/null)
    if rpm -q "$name.x86_64" >/dev/null 2>&1; then
        want+=("$rpm")
    else
        echo "skipping $(basename "$rpm"): $name.x86_64 is not installed"
    fi
done
printf 'installing: %s\n' "${want[@]##*/}"
dnf5 -y install "${want[@]}"

# Every i686 NVIDIA package must match its x86_64 twin, and the driver must
# match the kernel module.
status=0
while read -r name evr; do
    x86=$(rpm -q --qf '%{EVR}' "$name.x86_64")
    printf '%-32s i686 %s  x86_64 %s\n' "$name" "$evr" "$x86"
    [[ $evr == "$x86" ]] || status=1
done < <(rpm -qa --queryformat '%{NAME} %{EVR} %{ARCH}\n' |
    awk '$3 == "i686" && $1 ~ /^(nvidia-|libnvidia-)/ { print $1, $2 }' | sort)
kmod=$(rpm -q --qf '%{VERSION}' kmod-nvidia)
driver=$(rpm -q --qf '%{VERSION}' nvidia-driver)
echo "kmod-nvidia $kmod, nvidia-driver $driver"
[[ $kmod == "$driver" ]] || status=1
if ((status != 0)); then
    echo "NVIDIA version mismatch, see above" >&2
    exit 1
fi
