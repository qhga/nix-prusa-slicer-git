# Author: phga <phga@posteo.de>
# Most of the code is copypasta of the official package from the nixpkgs repo.
# Some of the parts are copypasta of the derivation from @dmayle https://github.com/NixOS/nixpkgs/issues/222937
{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }@inputs: {

    packages.x86_64-linux.default =

      with import nixpkgs { system = "x86_64-linux"; };
      let
        # https://github.com/dmayle/nix-config/blob/main/packages/prusa-slicer-alpha.nix
        wxGTK-prusa = wxGTK32.overrideAttrs (old: rec {
          pname = "wxwidgets-prusa3d-patched";
          version = "3.2.0";
          configureFlags = old.configureFlags ++ [ "--disable-glcanvasegl" ];
          preConfigure = old.preConfigure + ''
    sed -ie 's@^\t\(monodll_msw_secretstore\|monolib_msw_secretstore\|basedll_msw_secretstore\|coredll_dark_mode\|monodll_dark_mode\|monolib_dark_mode\|baselib_msw_secretstore\|corelib_dark_mode\)\.o$@\t\1.o \\@' Makefile.in
    '';
          src = fetchFromGitHub {
            owner = "prusa3d";
            repo = "wxWidgets";
            rev = "4fd2120c913c20c3bb66ee9d01d8ff5087a8b90a";
            sha256 = "sha256-heWjXXlxWo7xBxh0A0Q141NrPTZplaUNZsUtvlRCvBw=";
            fetchSubmodules = true;
          };
        });

        # https://github.com/dmayle/nix-config/blob/main/packages/prusa-slicer-alpha.nix
        openvdb_tbb_2021_8 = openvdb.overrideAttrs (old: rec {
          buildInputs = [ openexr boost tbb_2021_8 jemalloc c-blosc ilmbase ];
        });

        nanosvg  = stdenv.mkDerivation {
          pname = "nanosvg";
          version = "1";

          src = fetchFromGitHub {
            owner = "fltk";
            repo = "nanosvg";
            rev = "abcd277ea45e9098bed752cf9c6875b533c0892f";
            sha256 = "sha256-WNdAYu66ggpSYJ8Kt57yEA4mSTv+Rvzj9Rm1q765HpY=";
          };

          nativeBuildInputs = [ cmake ];
        };
      in stdenv.mkDerivation rec {
        pname = "prusa-slicer";
        version = "2.6.0-alpha5";

        nativeBuildInputs = [
          cmake
          pkg-config
          wrapGAppsHook
          copyDesktopItems
        ];

        buildInputs = [
          binutils
          boost
          cereal
          cgal_5
          curl
          dbus
          eigen
          expat
          glew
          glib
          gmp
          gtk3
          hicolor-icon-theme
          ilmbase
          libpng
          mpfr
          nlopt
          opencascade-occt
          pcre
          wxGTK-prusa
          xorg.libX11
          systemd
          qhull
          nanosvg
          openvdb_tbb_2021_8
          tbb_2021_8
        ] ++ nativeCheckInputs;

        doCheck = true;
        nativeCheckInputs = [ gtest ];
        separateDebugInfo = true;

        # The build system uses custom logic - defined in
        # cmake/modules/FindNLopt.cmake in the package source - for finding the nlopt
        # library, which doesn't pick up the package in the nix store.  We
        # additionally need to set the path via the NLOPT environment variable.
        NLOPT = nlopt;

        # Disable compiler warnings that clutter the build log.
        # It seems to be a known issue for Eigen:
        # http://eigen.tuxfamily.org/bz/show_bug.cgi?id=1221
        env.NIX_CFLAGS_COMPILE = "-Wno-ignored-attributes";

        # prusa-slicer uses dlopen on `libudev.so` at runtime
        NIX_LDFLAGS = "-ludev";

        prePatch = ''
          # Since version 2.5.0 of nlopt we need to link to libnlopt, as libnlopt_cxx
          # now seems to be integrated into the main lib.
          sed -i 's|nlopt_cxx|nlopt|g' cmake/modules/FindNLopt.cmake
          # Disable test_voronoi.cpp as the assembler hangs during build,
          # likely due to commit e682dd84cff5d2420fcc0a40508557477f6cc9d3
          # See issue #185808 for details.
          sed -i 's|test_voronoi.cpp||g' tests/libslic3r/CMakeLists.txt
          # Disable slic3r_jobs_tests.cpp as the test fails
          sed -i 's|slic3r_jobs_tests.cpp||g' tests/slic3rutils/CMakeLists.txt
          # prusa-slicer expects the OCCTWrapper shared library in the same folder as
          # the executable when loading STEP files. We force the loader to find it in
          # the usual locations (i.e. LD_LIBRARY_PATH) instead. See the manpage
          # dlopen(3) for context.
          if [ -f "src/libslic3r/Format/STEP.cpp" ]; then
          substituteInPlace src/libslic3r/Format/STEP.cpp \
              --replace 'libpath /= "OCCTWrapper.so";' 'libpath = "OCCTWrapper.so";'
          fi
          #
          # https://github.com/prusa3d/PrusaSlicer/issues/9581
          rm cmake/modules/FindEXPAT.cmake
        '';

        src = fetchFromGitHub {
          owner = "prusa3d";
          repo = "PrusaSlicer";
          # sha256 = "sha256-wLe+5TFdkgQ1mlGYgp8HBzugeONSne17dsBbwblILJ4=";
          sha256 = "sha256-sIbwuB1Ai2HrzN7tYm6gDL4aCppRcgjsdkuqQTTD3d0=";
          rev = "version_${version}";
        };

        cmakeFlags = [
          "-DSLIC3R_STATIC=0"
          "-DSLIC3R_FHS=1"
          "-DSLIC3R_GTK=3"
          # "-DCMAKE_PREFIX_PATH=${nanosvg}"
        ];

        postInstall = ''
          ln -s "$out/bin/prusa-slicer" "$out/bin/prusa-gcodeviewer"
          mkdir -p "$out/lib"
          mv -v $out/bin/*.* $out/lib/
          mkdir -p "$out/share/pixmaps/"
          ln -s "$out/share/PrusaSlicer/icons/PrusaSlicer.png" "$out/share/pixmaps/PrusaSlicer.png"
          ln -s "$out/share/PrusaSlicer/icons/PrusaSlicer-gcodeviewer_192px.png" "$out/share/pixmaps/PrusaSlicer-gcodeviewer.png"
        '';

        preFixup = ''gappsWrapperArgs+=(--prefix LD_LIBRARY_PATH : "$out/lib")'';

        desktopItems = [
          (makeDesktopItem {
            name = "PrusaSlicer";
            desktopName = "PrusaSlicer (git)";
            exec = "prusa-slicer %F";
            icon = "PrusaSlicer";
          })
        ];

        meta = {
          homepage = "https://github.com/prusa3d/PrusaSlicer";
          description = "G-code generator for 3D printer";
          platforms = lib.platforms.linux;
        };
      };
  };
}