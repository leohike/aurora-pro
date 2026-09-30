# aurora-pro

Personal BlueBuild image: `ghcr.io/ublue-os/aurora-dx:stable` + kvantum, snapper,
btrfs-assistant, btrbk, and a native Steam/Wine/Lutris stack from negativo17.
Published to `ghcr.io/mithrandir4859/aurora-pro`. Recipe: `recipes/recipe.yml`;
CI: `.github/workflows/build.yml`.

## Background docs (read before changing the recipe)

In `/home/shared/kb/curated/`:

- `from-conversations/custom-aurora-dx-image-steam-wine-and-bazzite-parts.md`:
  why this image exists, signing and the first rebase, why Steam/Wine can only be
  baked (not layered), negativo17 vs RPMFusion, what was taken from Bazzite and
  what was left out, the NVIDIA/Pascal dead end. **The main design record.**
- `from-conversations/virtualization-on-aurora-dx-what-it-gives-you.md`: what the
  DX virt stack gives you, and that VT-x is off in the T590 firmware.
- `from-conversations/mullvad-on-aurora-and-the-tailscale-conflict.md`: whether
  Mullvad belongs in the image (no), and the Tailscale conflict.
- `from-downloads/Btrfs Snapshot & Subvolume Backups for User Data on Fedora Aurora KDE.md`:
  the reasoning behind snapper/btrfs-assistant/btrbk (snapshot `/var/home`, never `/`).

## Upstream reference repos

Read-only clones in `/home/shared/projects/`. Quote them rather than guessing:

- `aurora/`: ublue-os/aurora. The base image. Build cadence is in
  `.github/workflows/trigger-schedule-stable-image.yml` (`:stable` is built
  weekly, Tuesday 01:00 UTC, plus off-cycle hotfix builds).
- `bazzite/`, `bazzite-dx/`: ublue-os/bazzite{,-dx}. Where the gaming parts
  came from. Most of what's left there needs Bazzite's kernel.
- `modules/`: blue-build/modules. Source for the recipe's module types (`dnf`,
  `files`, `signing`, ...).
- `secureblue/`: another BlueBuild-based image, useful as a recipe/CI example.

## CI: builds only when something changed

`.github/scripts/fingerprint.sh` hashes the base image digest, `recipes/` +
`files/` + `.github/`, and the newest repo versions of every package the recipe
installs (~15 s, no base image pull). The gate job compares it with the
`org.aurora-pro.fingerprint` label on the published image and skips the build if
equal. main is checked every 2 hours and on push, and publishes `:latest`.
Manual runs build unless `force` is off.

`dev` is a throwaway branch: create it when needed, delete it after merging.
While it exists, pushes to it build (gated), and since schedules only fire on
the default branch, `.github/workflows/schedule-dev.yml` on main dispatches its
gated check every 2 hours (a no-op while there is no `dev`). `dev` builds
publish `aurora-pro:dev`.
