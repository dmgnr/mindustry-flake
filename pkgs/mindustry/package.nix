{
  lib,
  stdenv,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  fetchFromGitHub,
  gradle,
  jdk17,
  zenity,

  SDL2,
  pkg-config,
  ant,
  curl,
  wget,
  alsa-lib,
  alsa-plugins,
  glew,

  libpulseaudio ? null,
  libjack2 ? null,

  # overridables
  makeBuildVersion ? (v: v),
  enableClient ? true,
  enableServer ? true,
  enableWayland ? false,
}:

let
  pname = "mindustry";
  version = "154.3";
  buildVersion = makeBuildVersion version;

  jdk = jdk17;

  Mindustry = fetchFromGitHub {
    name = "Mindustry-source";
    owner = "Anuken";
    repo = "Mindustry";
    tag = "v${version}";
    hash = "sha256-yVrOHZOCZrI5SsmMdo7Eh+zS0PXv2X67zLCdLOWcPVc=";
  };

  Arc = fetchFromGitHub {
    name = "Arc-source";
    owner = "Anuken";
    repo = "Arc";
    tag = "v${version}";
    hash = "sha256-JyiFxzdZtU0ILytTCfZrhBU2oZ3gF1kzMbSdjxqvTYs=";
  };

  soloud = fetchFromGitHub {
    owner = "Anuken";
    repo = "soloud";
    tag = "v0.11";
    hash = "sha256-jybIILdK3cqyZ2LIuoWDfZWocVTbKszekKCLil0WXRY=";
  };

  desktopItem = makeDesktopItem {
    name = "Mindustry";
    desktopName = "Mindustry";
    exec = "mindustry";
    icon = "mindustry";
    categories = [ "Game" ];
  };

in
assert lib.assertMsg (
  enableClient || enableServer
) "mindustry: at least one of 'enableClient' and 'enableServer' must be true";

stdenv.mkDerivation {
  inherit pname version;

  unpackPhase = ''
    runHook preUnpack

    cp -r ${Mindustry} Mindustry
    cp -r ${Arc} Arc
    chmod -R u+w -- Mindustry Arc
    cp -r ${soloud} Arc/arc-core/csrc/soloud
    chmod -R u+w -- Arc/arc-core/csrc/soloud

    runHook postUnpack
  '';

  patches = [
    ./0001-fix-include-path-for-SDL2-on-linux.patch
  ];

  postPatch = ''
    rm -r Arc/natives/natives-*/libs/* || true
    rm -r Arc/backends/backend-*/libs/* || true

    cd Mindustry

    sed -i '/^project(":ios"){/,/^}/d' build.gradle
    sed -i '/robo(vm|VM)/d' build.gradle
    rm -f ios/build.gradle
  ''
  + lib.optionalString (!stdenv.hostPlatform.isx86) ''
    substituteInPlace ../Arc/arc-core/build.gradle \
      --replace-fail "-msse" ""
    substituteInPlace ../Arc/backends/backend-sdl/build.gradle \
      --replace-fail "-m64" ""
  '';

  mitmCache = gradle.fetchDeps {
    inherit pname;
    data = ./deps.json;
  };

  __darwinAllowLocalNetworking = true;

  buildInputs = lib.optionals enableClient [
    SDL2
    alsa-lib
    glew
  ];

  nativeBuildInputs = [
    pkg-config
    gradle
    makeWrapper
    jdk
  ]
  ++ lib.optionals enableClient [
    ant
    copyDesktopItems
    curl
    wget
  ];

  desktopItems = lib.optional enableClient desktopItem;

  gradleFlags = [
    "-Pbuildversion=${buildVersion}"
    "-Dorg.gradle.java.home=${jdk}"
  ];

  buildPhase = ''
    runHook preBuild
  ''
  + lib.optionalString enableServer ''
    gradle server:dist
  ''
  + lib.optionalString enableClient ''
    pushd ../Arc
    gradle jnigenBuild -x jnigenBuildAndroid -x jnigenBuildWindows -x jnigenBuildWindows64
    gradle jnigenJarNativesDesktop
    glewlib=${lib.getLib glew}/lib/libGLEW.so
    sdllib=${lib.getLib SDL2}/lib/libSDL2.so
    patchelf backends/backend-sdl/build/Arc/backends/backend-sdl/libs/linux64/libsdl-arc*.so \
      --add-needed "$glewlib" \
      --add-needed "$sdllib"
    cp arc-core/build/Arc/arc-core/libs/*/* natives/natives-desktop/libs/
    cp backends/backend-sdl/build/Arc/backends/backend-sdl/libs/*/* natives/natives-desktop/libs/
    cp extensions/freetype/build/Arc/extensions/freetype/libs/*/* natives/natives-freetype-desktop/libs/
    cp extensions/filedialogs/build/Arc/extensions/filedialogs/libs/*/* natives/natives-filedialogs/libs/
    popd

    gradle desktop:dist
  ''
  + ''
    runHook postBuild
  '';

  installPhase =
    let
      installClient = ''
        install -Dm644 desktop/build/libs/Mindustry.jar $out/share/mindustry.jar
        mkdir -p $out/bin
        makeWrapper ${jdk}/bin/java $out/bin/mindustry \
          --add-flags "-jar $out/share/mindustry.jar" \
          ${lib.optionalString stdenv.hostPlatform.isLinux "--suffix PATH : ${lib.makeBinPath [ zenity ]}"} \
          --suffix LD_LIBRARY_PATH : ${
            lib.makeLibraryPath [
              libpulseaudio
              alsa-lib
              libjack2
            ]
          } \
          --set ALSA_PLUGIN_DIR ${alsa-plugins}/lib/alsa-lib/ \
          ${lib.optionalString enableWayland ''
            --set SDL_VIDEODRIVER wayland \
            --set SDL_VIDEO_WAYLAND_WMCLASS Mindustry
          ''}

        echo "# Retained runtime dependencies: " >> $out/bin/mindustry
        for dep in ${SDL2.out} ${alsa-lib.out} ${glew.out}; do
          echo "# $dep" >> $out/bin/mindustry
        done

        install -Dm644 core/assets/icons/icon_64.png \
          $out/share/icons/hicolor/64x64/apps/mindustry.png
      '';

      installServer = ''
        install -Dm644 server/build/libs/server-release.jar $out/share/mindustry-server.jar
        mkdir -p $out/bin
        makeWrapper ${jdk}/bin/java $out/bin/mindustry-server \
          --add-flags "-jar $out/share/mindustry-server.jar"
      '';
    in
    ''
      runHook preInstall
    ''
    + lib.optionalString enableClient installClient
    + lib.optionalString enableServer installServer
    + ''
      runHook postInstall
    '';

  postGradleUpdate = ''
    cd ../Arc
    gradle preJni
  '';

  meta = {
    homepage = "https://mindustrygame.github.io/";
    downloadPage = "https://github.com/Anuken/Mindustry/releases";
    description = "Sandbox tower defense game";
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
    ];
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.all;

    broken =
      enableClient
      && (stdenv.hostPlatform.isDarwin || (stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isAarch64));
  };
}
