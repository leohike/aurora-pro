#!/usr/bin/env bash
# 32-bit NVIDIA libraries for aurora-max-nvidia.
#
# aurora-dx-nvidia-open installs the driver with MULTILIB=0
# (ublue-os/aurora build_scripts/base/04-nvidia.sh): no i686 NVIDIA libraries,
# because Aurora's Steam is a Flatpak that brings its own. A native Steam and
# Wine need them on the host, or 32-bit OpenGL/Vulkan programs cannot use the
# NVIDIA GPU.
#
# Every i686 package is pinned to the exact version of its installed x86_64
# twin, which matches the prebuilt kernel module. Asking for "latest" instead
# would, once negativo17 ships a newer driver than Aurora, drag the 64-bit
# libraries along and break the match with the kernel module. Pinned, the worst
# case is a failed build, never a broken image.
#
# Same set as ublue-os/akmods nvidia-install.sh installs with MULTILIB=1, from
# the repo Aurora's driver comes from. Unique repo ids so nothing collides with
# repo files the base image ships.
set -euo pipefail

fedora=$(rpm -E %fedora)
key=https://negativo17.org/repos/RPM-GPG-KEY-slaanesh
repos=(
    --repofrompath="aurora-max-nvidia,https://negativo17.org/repos/nvidia/fedora-$fedora/x86_64/"
    --repofrompath="aurora-max-multimedia,https://negativo17.org/repos/multimedia/fedora-$fedora/x86_64/"
)
for id in aurora-max-nvidia aurora-max-multimedia; do
    repos+=(--setopt="$id.gpgcheck=1" --setopt="$id.gpgkey=$key" --setopt="$id.priority=90")
done

mapfile -t nvidia < <(rpm -qa --queryformat '%{NAME} %{ARCH}\n' |
    awk '$2 == "x86_64" && $1 ~ /^(nvidia-|libnvidia-)/ { print $1 }' | sort -u)
echo "installed x86_64 NVIDIA packages: ${nvidia[*]}"

want=()
for name in "${nvidia[@]}"; do
    evr=$(rpm -q --qf '%{EVR}' "$name.x86_64")
    if [[ -n $(dnf5 -q "${repos[@]}" repoquery --arch=i686 "$name-$evr") ]]; then
        want+=("$name-$evr.i686")
    else
        echo "no i686 build of $name-$evr, skipping"
    fi
done
if ((${#want[@]} == 0)); then
    echo "found no i686 NVIDIA packages to install; repo layout changed?" >&2
    exit 1
fi

echo "installing: ${want[*]}"
dnf5 -y "${repos[@]}" install "${want[@]}"

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
