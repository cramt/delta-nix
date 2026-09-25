# Delta — Zed's standalone AI coding agent (https://delta.dev). Not the same
# thing as nixpkgs' `delta`, which is dandavison's git-delta pager, but the
# binary is also named `delta`, so only put one of the two on a given PATH.
#
# The tarballs sit in a private R2 bucket. delta.dev's (unauthenticated)
# releases API only ever hands out presigned links that die after 15 minutes,
# so there is no URL fetchurl could pin. Instead src is a fixed-output
# derivation that asks the API for a fresh link to the *pinned* version at
# fetch time: the hash keeps it reproducible, the API just brokers access.
# Swap for plain fetchurl if upstream ever publishes a stable URL.
#
# Upstream ships bin/delta with RPATH=$ORIGIN/../lib and its own copies of
# libxcb/libxkbcommon (plus libunwind on x86_64), built for old-glibc distros.
# We drop that lib/ directory and let autoPatchelf link the nixpkgs ones
# instead — all stable-soname libraries, and vendoring them would just freeze a
# second unpatched copy into the closure.
#
# GPUI reaches libwayland-client/libwayland-egl/libvulkan/libEGL through
# dlopen, which autoPatchelf cannot see, so those go in the wrapper's
# LD_LIBRARY_PATH along with the driver link that carries the Vulkan ICD.
#
# version + hashes live in sources.json, rewritten by `nix run .#update`.
{
  lib,
  stdenv,
  stdenvNoCC,
  curl,
  jq,
  cacert,
  autoPatchelfHook,
  makeWrapper,
  addDriverRunpath,
  libxkbcommon,
  llvmPackages,
  libglvnd,
  vulkan-loader,
  wayland,
  libxcb,
}: let
  sources = lib.importJSON ./sources.json;
  inherit (sources) version;
  system = stdenv.hostPlatform.system;
  arch = stdenv.hostPlatform.parsed.cpu.name;
in
  stdenv.mkDerivation {
    pname = "delta";
    inherit version;

    src = stdenvNoCC.mkDerivation {
      name = "delta-linux-${arch}-${version}.tar.gz";
      outputHashMode = "flat";
      outputHashAlgo = "sha256";
      outputHash = sources.hashes.${system} or (throw "delta: no release for ${system}");
      nativeBuildInputs = [curl jq];
      SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
      impureEnvVars = lib.fetchers.proxyImpureEnvVars;
      buildCommand = ''
        url=$(curl -fsSL "https://delta.dev/api/releases/nightly/${version}/asset?asset=delta&os=linux&arch=${arch}" | jq -er .url)
        curl -fsSL -o "$out" "$url"
      '';
    };

    nativeBuildInputs = [autoPatchelfHook makeWrapper];

    buildInputs = [
      libxcb
      libxkbcommon
      # LLVM's libunwind, not nixpkgs' nongnu `libunwind` — only the LLVM one
      # carries soname libunwind.so.1, which is what upstream linked against.
      # Unused (and so left out of the RPATH) on aarch64, which doesn't link it.
      llvmPackages.libunwind
    ];

    # The tarball's install.sh only copies the bundle into ~/.local and rewrites
    # the .desktop Exec; we do the same thing declaratively and skip the script.
    installPhase = ''
      runHook preInstall

      rm -rf lib
      mkdir -p $out/bin $out/share
      cp -a bin/delta $out/bin/delta
      cp -a share/icons $out/share/icons

      install -Dm644 share/applications/dev.zed.Delta.desktop \
        $out/share/applications/dev.zed.Delta.desktop
      substituteInPlace $out/share/applications/dev.zed.Delta.desktop \
        --replace-fail "Exec=delta " "Exec=$out/bin/delta "

      runHook postInstall
    '';

    postFixup = ''
      wrapProgram $out/bin/delta \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [wayland vulkan-loader libglvnd]}:${addDriverRunpath.driverLink}/lib"
    '';

    meta = {
      description = "Zed's standalone AI coding agent";
      homepage = "https://delta.dev";
      license = lib.licenses.unfree;
      platforms = builtins.attrNames sources.hashes;
      mainProgram = "delta";
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
