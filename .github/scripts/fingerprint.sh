#!/usr/bin/env bash
# Prints one sha256 that changes whenever a build of this recipe would come out
# different, without building or pulling the base image:
#   - the base image digest (Aurora published a new stable)
#   - our own inputs: recipes/, files/, .github/
#   - the newest available version of every package the recipe's dnf modules
#     install, queried from a small Fedora container with the same repos added
#
# Blind spot, on purpose: an update to a dependency of those packages alone
# (say an i686 lib under Wine) does not change the hash. It rides along with the
# next real build -- at worst Aurora's next weekly stable.
#
# The inputs are printed to stderr so a CI log shows why the hash changed.
# Needs: bash, yq (mikefarah), jq, skopeo, podman, sha256sum.
set -euo pipefail

recipe=${1:-recipes/recipe.yml}
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

# What BlueBuild's dnf module adds for `nonfree: negativo17` (blue-build/modules,
# modules/dnf/dnf.nu).
negativo17_url=https://negativo17.org/repos/fedora-negativo17.repo

base_ref="$(yq '.["base-image"]' "$recipe"):$(yq '.["image-version"]' "$recipe")"
base_json=$(skopeo inspect --no-tags "docker://$base_ref")
base_digest=$(jq -r .Digest <<<"$base_json")
fedora=$(jq -r '.Labels["org.opencontainers.image.version"]' <<<"$base_json" | cut -d. -f1)

# All of recipes/, not just this recipe: the recipes share modules via `from-file:`.
inputs_hash=$(find recipes files .github -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)

# The recipe's modules, one JSON object per line, with `from-file:` includes
# (resolved against recipes/, like BlueBuild does) expanded in place.
modules() {
    local module include
    while read -r module; do
        include=$(jq -r '.["from-file"] // empty' <<<"$module")
        if [[ -n $include ]]; then
            modules "recipes/$include"
        else
            echo "$module"
        fi
    done < <(yq -o=json -I=0 '.modules[]' "$1")
}
dnf_modules=$(modules "$recipe" | jq -c 'select(.type == "dnf")')

if [[ -n $(jq '.repos // {} | select(.copr != null or (.nonfree != null and .nonfree != "negativo17"))' <<<"$dnf_modules") ]]; then
    echo "fingerprint.sh: recipe uses a dnf repo kind this script does not replicate (copr/rpmfusion); teach it first" >&2
    exit 1
fi
mapfile -t repo_urls < <(
    jq -r '.repos.files // [] | .[]' <<<"$dnf_modules"
    jq -r --arg url "$negativo17_url" 'select(.repos.nonfree == "negativo17") | $url' <<<"$dnf_modules"
)
mapfile -t packages < <(jq -r '.install.packages // [] | .[]' <<<"$dnf_modules")

versions=$(podman run --rm -e REPOS="${repo_urls[*]}" \
    "registry.fedoraproject.org/fedora:$fedora" bash -c '
    set -euo pipefail
    for url in $REPOS; do curl -fsSL -o "/etc/yum.repos.d/$(basename "$url")" "$url"; done
    dnf5 -q repoquery --latest-limit=1 --arch=x86_64,i686,noarch \
        --qf "%{name}-%{evr}.%{arch}\n" "$@" | sort -u' _ "${packages[@]}")

{
    echo "base $base_ref $base_digest"
    echo "inputs $inputs_hash"
    echo "$versions"
} | tee /dev/stderr | sha256sum | cut -d' ' -f1
