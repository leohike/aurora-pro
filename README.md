# aurora-max

Personal [Aurora DX](https://getaurora.dev/) images with a few packages baked in, built by [BlueBuild](https://blue-build.org/):

| Image | Base | For |
|---|---|---|
| `ghcr.io/leohike/aurora-max` | `ghcr.io/ublue-os/aurora-dx:stable` | machines without an NVIDIA GPU |
| `ghcr.io/leohike/aurora-max-nvidia` | `ghcr.io/ublue-os/aurora-dx-nvidia-open:stable` | NVIDIA Turing or newer (built for an RTX A3000) |

Both carry the same packages (`recipes/common.yml`). Until 2026-10 the first one was published as `ghcr.io/leohike/aurora-max`.

## Why this exists

Some packages were layered with `rpm-ostree install`, and some can't be layered on Aurora at all.

- **Steam can't be layered.** Aurora edits the default icon theme, so layering `libXcursor` fails with a hardlink error (`ublue-os/bluefin#1258`, closed "not planned"). A container build has no ostree hardlinking, so it installs cleanly.
- **Wine can't be layered either.** The i686 packages hit the same class of hardlink failure (RHBZ #1846803, rpm-ostree#1937). A system-wide `wine foo.exe` is only possible from an image.
- **Layering has a recurring cost.** It slows every update, can block upgrades and must be cleared before a major rebase. An image costs a fixed setup up front, and then each extra package costs nothing.

It derives from the upstream image instead of forking `ublue-os/aurora`, so there are no merge conflicts to chase. A gated check every 2 hours picks up Aurora and package updates automatically.

What belongs in the image: things that need to write to `/usr`, own a system-wide default, or load into the kernel. GUI apps go in Flatpak, CLI tools in Homebrew, and everything else in Distrobox.

## What's in it

See `recipes/common.yml`, which also explains each choice in its comments. `recipes/recipe.yml` and `recipes/recipe-nvidia.yml` only add the base image and what differs.

- `kvantum` (Qt style engine), `snapper` (btrfs snapshots), `btrfs-assistant` (its GUI, which brings `btrfsmaintenance` along as a weak dependency) and `btrbk` (send/receive backups, unconfigured).
- Gaming, from negativo17 (the same repo family Aurora's Mesa comes from, so the 32-bit stack matches): `steam`, `steam-devices`, `gamescope`, `mangohud`.
- Wine as a host tool: `wine`, `wine-core.i686`, `wine-pulseaudio.i686`, `wine-mono`, `winetricks`, `lutris`.
- The BlueBuild `signing` module, so machines verify the image's signature.
- `aurora-max-nvidia` only: the 32-bit NVIDIA libraries (`files/scripts/nvidia-multilib.sh`), pinned to the installed driver. Aurora leaves them out because its Steam is a Flatpak; a native Steam and Wine need them for 32-bit games on the NVIDIA GPU. The driver itself, CUDA support (`libcuda`, `nvidia-smi`) and `nvidia-container-toolkit` come from Aurora. The CUDA toolkit (`nvcc`) belongs in a container or distrobox.

## Builds and tags

GitHub Actions (`.github/workflows/build.yml`) checks every 2 hours, on every push, on pull requests and on manual dispatch, one job per image. A build only runs when `.github/scripts/fingerprint.sh` (base image digest, this repo's files, newest versions of the recipe's packages) differs from the `org.aurora-max.fingerprint` label on the published image. Manual runs build anyway unless `force` is unticked.

| Tag | Meaning |
|---|---|
| `latest` | Newest build of `main`. Follow this one. |
| `44`, `20260921`, `20260921-44` | Fedora version and build date, from `main`. |
| `<sha>-44` (e.g. `8e408e3-44`) | A specific commit's build. Pin to it to go back to a known-good image. |
| `dev` | Newest build of the `dev` branch, checked every 2 hours while the branch exists. |
| `br-<branch>-44` (e.g. `br-steam2-44`) | Latest push to a non-default branch, for trying changes before merging. |

The build keeps the Fedora version from the base image, so `latest` won't jump to a new Fedora release until Aurora `stable` does.

## Installing on a machine

The machine's `/etc/containers/policy.json` rejects signed images from unknown namespaces. The image carries its own trust policy, so the first rebase is unverified, and after that everything is signed. This is needed once per machine and image name, not per tag (so also when moving from `aurora-pro` to `aurora-max`).

On an NVIDIA machine use `aurora-max-nvidia` below, and if it isn't on a Universal Blue NVIDIA image already, enroll their Secure Boot key first (`ujust enroll-secure-boot-key`), since the prebuilt driver module is signed with it.

```bash
# optional: verify the image out-of-band first (cosign.pub is in this repo)
cosign verify --key cosign.pub ghcr.io/leohike/aurora-max:latest

rpm-ostree rebase ostree-unverified-registry:ghcr.io/leohike/aurora-max:latest
systemctl reboot

rpm-ostree rebase ostree-image-signed:docker://ghcr.io/leohike/aurora-max:latest
systemctl reboot
```

Remove any layered packages the image now provides, for example `rpm-ostree uninstall kvantum`, before or after the rebase.

## Day to day

```bash
# what am I running, and what's staged
rpm-ostree status

# switch tag (a branch build, a pinned commit, back to latest)
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/leohike/aurora-max:latest
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/leohike/aurora-max:8e408e3-44

# update now instead of waiting for uupd.timer (Aurora's updater, runs daily)
sudo rpm-ostree upgrade

# boot the previous deployment (also selectable in GRUB)
sudo rpm-ostree rollback

# back to stock Aurora
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/ublue-os/aurora-dx:stable
```

Checking builds and published images:

```bash
gh run list -R leohike/aurora-max        # or the repo's Actions tab
gh run watch -R leohike/aurora-max

skopeo list-tags docker://ghcr.io/leohike/aurora-max
skopeo inspect docker://ghcr.io/leohike/aurora-max:latest   # build date, Aurora version, digest

# what a build actually contains
podman run --rm ghcr.io/leohike/aurora-max:latest rpm -q steam wine lutris
```

## Changing the image

Edit the recipes on the `dev` branch and push. It builds both images as `:dev`; rebase one machine to it, try it, then merge into `main` and delete `dev`. Files placed under `files/system/` are copied into the image root.

Before adding a package, check it against the live package set, for example `dnf5 install --assumeno <pkg>` in a container of `aurora-dx:stable`, so the dependency count holds no surprises.

## Signing

Images are signed with [cosign](https://github.com/sigstore/cosign). `cosign.pub` is committed. The private key is the `SIGNING_SECRET` repository secret; `cosign.key` is gitignored and must never be committed.
