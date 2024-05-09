{
  description = "K Framework";
  inputs = {
    haskell-backend.url = "github:runtimeverification/haskell-backend/88ef647ec106b3ba1612ea848a61ba3c2fd3f786";
    nixpkgs.follows = "llvm-backend/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    llvm-backend = {
      url = "github:runtimeverification/llvm-backend/v0.1.10";
      inputs.utils.follows = "flake-utils";
    };
    rv-utils.url = "github:runtimeverification/rv-nix-tools";
  };

  outputs = { self, nixpkgs, flake-utils, rv-utils, haskell-backend
    , llvm-backend }:
    let
      allOverlays = [
        (_: _: {
          llvm-version = 15;
          llvm-backend-build-type = "Release";
        })
        llvm-backend.overlays.default
        haskell-backend.overlays.z3
        haskell-backend.overlays.integration-tests
        (final: prev:
          let
            k-version =
              prev.lib.removeSuffix "\n" (builtins.readFile ./package/version);
            src = prev.stdenv.mkDerivation {
              name = "k-${k-version}-${self.rev or "dirty"}-src";
              src = prev.lib.cleanSource
                (prev.nix-gitignore.gitignoreSourcePure [
                  ./.gitignore
                  ".github/"
                  "result*"
                  "nix/"
                  "*.nix"
                  "haskell-backend/src/main/native/haskell-backend/*"
                  "llvm-backend/src/main/native/llvm-backend/*"
                  "k-distribution/tests/regression-new"
                ] ./.);
              dontBuild = true;
              installPhase = ''
                mkdir $out
                cp -rv $src/* $out
                chmod -R u+w $out
                mkdir -p $out/llvm-backend/src/main/native/llvm-backend/matching
                cp -rv ${llvm-backend}/matching/* $out/llvm-backend/src/main/native/llvm-backend/matching
              '';
            };
          in {
            # this version of maven from nixpkgs 23.11. we can remove this version of maven once our nixpkgs catches up
            maven = prev.callPackage ./nix/maven.nix { };

            k-framework = { haskell-backend-bins, llvm-kompile-libs }:
              prev.callPackage ./nix/k.nix {
                mvnHash = "sha256-DnY+Zx4fr3iuI24VjlnCVeQCcK6aHYYAEW13aUEzd+I=";
                manualMvnArtifacts = [
                  "org.scala-lang:scala-compiler:2.13.13"
                  "ant-contrib:ant-contrib:1.0b3"
                  "org.apache.ant:ant-nodeps:1.8.1"
                  "org.apache.maven.wagon:wagon-provider-api:1.0-alpha-6"
                  "org.checkerframework:checker-qual:3.33.0"
                  "com.google.errorprone:error_prone_annotations:2.18.0"
                ];
                manualMvnSourceArtifacts = [
                  "org.scala-sbt:compiler-bridge_2.13:1.8.0"
                ];
                inherit (final) maven;
                inherit (prev) llvm-backend;
                clang = prev."clang_${toString final.llvm-version}";
                haskell-backend = haskell-backend-bins;
                inherit (haskell-backend) prelude-kore;
                inherit src;
                debugger = if prev.stdenv.isDarwin then
                # lldb is broken on this version of nixpkgs-unstable and there is no point including it
                # before the lldb support for k is added: https://github.com/runtimeverification/k/issues/2650
                  null
                else
                  prev.gdb;
                version = "${k-version}-${self.rev or "dirty"}";
                inherit llvm-kompile-libs;
              };
          })
      ];
    in flake-utils.lib.eachSystem [
      "x86_64-linux"
      "x86_64-darwin"
      "aarch64-linux"
      "aarch64-darwin"
    ] (system:
      let
        pkgs = nixpkgs.lib.trivial.warnIf (llvm-backend.inputs.nixpkgs.rev
          != haskell-backend.inputs.nixpkgs.rev)
          "The version of nixpkgs in Haskell backend and LLVM backend has diverged!"
          import nixpkgs {
            inherit system;
            # Temporarily required until a bug on pyOpenSSL is resolved for aarch64-darwin
            # https://github.com/NixOS/nixpkgs/pull/172397
            config.allowBroken = system == "aarch64-darwin";
            overlays =
              [ (final: prev: { llvm-backend-build-type = "FastBuild"; }) ]
              ++ allOverlays;
          };

        haskell-backend-bins = pkgs.symlinkJoin {
          name = "kore-${haskell-backend.sourceInfo.shortRev or "local"}";
          paths = let p = haskell-backend.packages.${system};
          in [
            p.kore-exec
            p.kore-match-disjunction
            p.kore-parser
            p.kore-repl
            p.kore-rpc
            p.kore-rpc-booster
            p.kore-rpc-client
          ];
        };

      in rec {
        k-version =
          pkgs.lib.removeSuffix "\n" (builtins.readFile ./package/version);

        packages = rec {
          k = pkgs.k-framework {
            inherit haskell-backend-bins;
            llvm-kompile-libs = with pkgs; {
              procps = [ "-I${procps}/include" "-L${procps}/lib" ];
              openssl = [ "-I${openssl.dev}/include" "-L${openssl.out}/lib" ];
              secp256k1 = [ "-I${secp256k1}/include" "-L${secp256k1}/lib" ];
            };
          };

          check-submodules = rv-utils.lib.check-submodules pkgs {
            inherit llvm-backend haskell-backend;
          };

          smoke-test = with pkgs;
            stdenv.mkDerivation {
              name = "k-${k-version}-${self.rev or "dirty"}-smoke-test";
              src = lib.cleanSource
                (nix-gitignore.gitignoreSourcePure [ ./.gitignore ]
                  ./k-distribution);
              preferLocalBuild = true;
              buildInputs = [ lsof fmt gmp mpfr k ];
              buildFlags = [
                "K_BIN=${k}/bin"
                "KLLVMLIB=${k}/lib/kllvm"
                "PACKAGE_VERSION=${k-version}"
                "--output-sync"
              ];
              enableParallelBuilding = true;
              preBuild = ''
                cd tests/smoke
              '';
              installPhase = ''
                runHook preInstall
                touch "$out"
                runHook postInstall
              '';
            };

          test = with pkgs;
            stdenv.mkDerivation {
              name = "k-${k-version}-${self.rev or "dirty"}-test";
              src = lib.cleanSource
                (nix-gitignore.gitignoreSourcePure [ ./.gitignore ]
                  ./k-distribution);
              preferLocalBuild = true;
              buildInputs = [ fmt gmp mpfr k ];
              postPatch = ''
                patchShebangs tests/regression-new/*
                substituteInPlace tests/regression-new/append/kparse-twice \
                  --replace '"$(dirname "$0")/../../../bin/kparse"' '"${k}/bin/kparse"'
              '';
              buildFlags = [
                "K_BIN=${k}/bin"
                "KLLVMLIB=${k}/lib/kllvm"
                "PACKAGE_VERSION=${k-version}"
                "--output-sync"
              ];
              enableParallelBuilding = true;
              preBuild = ''
                cd tests/regression-new
              '';
              installPhase = ''
                runHook preInstall
                touch "$out"
                runHook postInstall
              '';
            };
        };
        defaultPackage = packages.k;
        devShells.kore-integration-tests = pkgs.kore-tests (pkgs.k-framework {
          inherit haskell-backend-bins;
          llvm-kompile-libs = { };
        });
      }) // {
        overlays.llvm-backend = llvm-backend.overlays.default;
        overlays.z3 = haskell-backend.overlays.z3;

        overlay = nixpkgs.lib.composeManyExtensions allOverlays;

      };
}
