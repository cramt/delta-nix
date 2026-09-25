# delta-nix

A Nix flake for [Delta](https://delta.dev), Zed's standalone AI coding agent,
on `x86_64-linux` and `aarch64-linux`.

A GitHub Action checks delta.dev every hour. When a new nightly is out, it
bumps `sources.json`, builds and runs the new version on both architectures,
and commits only if both pass.

Delta is proprietary. Using this flake means you accept Zed's
[terms](https://zed.dev/terms) and Delta's
[Early Access Agreement](https://delta.dev/early-access), the same as
downloading it from the website. This repository does not redistribute
Delta. The build downloads the release from delta.dev.

## Usage

Run it once:

```sh
nix run github:cramt/delta-nix
```

Install it from a flake with the overlay:

```nix
{
  inputs.delta-nix = {
    url = "github:cramt/delta-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # In your NixOS or Home Manager config:
  nixpkgs.overlays = [ inputs.delta-nix.overlays.default ];
  home.packages = [ pkgs.zed-delta ];
}
```

The overlay names the package `zed-delta`, because `pkgs.delta` in nixpkgs is
the git-delta diff pager. The binary is still called `delta`, so do not install
both on the same `PATH`.

The overlay follows your nixpkgs config, so you must allow unfree packages,
for example with `nixpkgs.config.allowUnfree = true`. The flake's own
`packages` output already allows Delta.

## How the download works

Delta's releases are in a private bucket. The releases API at
`https://delta.dev/api/releases/nightly/<version>/asset` needs no login. It
returns a download link that expires after 15 minutes. So `src` is a
fixed-output derivation that requests a new link for the pinned version each
time it fetches. The hash in `sources.json` keeps the build reproducible.

To update by hand, run `nix run .#update`.
