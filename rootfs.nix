{
  stdenv,
  runCommand,
  fetchurl,
  fetchgit,
  lib,
  buildPackages,
  mkpasswd,
  fakeroot,
  linux-gpuvm,
  pkgs
}:

let
  l4tVersion = "36.3.0";

  jetsonLinux = fetchurl {
    url = "https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v3.0/release/jetson_linux_r36.3.0_aarch64.tbz2";
    sha256 = "sha256-tGVlQIMedLkR4lBtLFZ8uxRv3dWUK2dfgML2ENakD0M=";
  };

  tegraRootfs = fetchurl {
    url = "https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v3.0/release/tegra_linux_sample-root-filesystem_r36.3.0_aarch64.tbz2";
    sha256 = "sha256-2UhqubVeViAZiMigXL9RRpgiijZg5BNa6MRN2TuK3rQ=";
  };

  nvgpuSrc = (fetchgit {
    url = "https://nv-tegra.nvidia.com/r/linux-nvgpu";
    rev = "jetson_36.3";
    hash = "sha256-+4xOrNtQ1emfgFyM4vqk7a7X+BoqH5+Do/wxyajLNMc=";
  }).overrideAttrs (old: {
    patches = [
      ./patches/0001-gpu-add-support-for-passthrough.patch
    ];
  });

  nvidiaOotSrc = fetchgit {
    url = "https://nv-tegra.nvidia.com/r/linux-nv-oot";
    rev = "jetson_36.3";
    hash = "sha256-l97Dq/WFOlxJVjoH63oUS5d1E+ax+aAz5CKTO678KnI=";
  };

  hwpmSrc = fetchgit {
    url = "https://nv-tegra.nvidia.com/r/linux-hwpm";
    rev = "jetson_36.3";
    hash = "sha256-YofkeKso43zK9vCOgPj5QFSdhPPsYtjhZpgh3RKyAPk=";
  };

  nvethernetrmSrc = fetchgit {
    url = "https://nv-tegra.nvidia.com/r/kernel/nvethernetrm";
    rev = "jetson_36.3";
    hash = "sha256-cTJagcO7TYG0eT0dgZn67hX/EKT04OrTYvwBwWEe1YU=";
  };

  t23xDtsSrc = fetchgit {
    url = "https://nv-tegra.nvidia.com/r/device/hardware/nvidia/t23x-public-dts";
    rev = "jetson_36.3";
    hash = "sha256-0A9dTe6wODuj/roRviWnEDeANW9tFlWWSe4gs5AfmB0=";
  };

  tegraPublicDtsSrc = fetchgit {
    url = "https://nv-tegra.nvidia.com/r/device/hardware/nvidia/tegra-public-dts";
    rev = "jetson_36.3";
    hash = "sha256-NMp7UY0OlH2ddBSrUzCUSLkvnWrELhz8xH/dkV86ids=";
  };

  nvdisplaySrc = fetchgit {
    url = "https://nv-tegra.nvidia.com/r/tegra/kernel-src/nv-kernel-display-driver";
    rev = "jetson_36.3";
    hash = "sha256-NZGzhJCXWdogatBAsIkldJ/kP1S3DaLHhR8nDyNsmNY=";
  };


  kernelIncludes = x: [
    "${linux-gpuvm.dev}/lib/modules/${linux-gpuvm.modDirVersion}/source/include"
    "${linux-gpuvm.dev}/lib/modules/${linux-gpuvm.modDirVersion}/source/arch/${stdenv.hostPlatform.linuxArch}/include"
    "${linux-gpuvm.dev}/lib/modules/${linux-gpuvm.modDirVersion}/source/include/uapi/"
    "${linux-gpuvm.dev}/lib/modules/${linux-gpuvm.modDirVersion}/source/arch/${stdenv.hostPlatform.linuxArch}/include/uapi/"
  ];

  source = runCommand "source" { } ''
    set -x

    echo
    echo Extract Jetson Linux
    tar -xf ${jetsonLinux}

    echo
    echo Copy modules sources
    cd Linux_for_Tegra/source/
    cp -r ${linux-gpuvm.src} kernel
    cp -r ${nvgpuSrc} nvgpu
    cp -r ${nvidiaOotSrc} nvidia-oot
    cp -r ${hwpmSrc} hwpm
    cp -r ${nvethernetrmSrc} nvethernetrm
    mkdir -p hardware/nvidia/t23x/nv-public
    cp -r ${t23xDtsSrc}/* hardware/nvidia/t23x/nv-public/
    mkdir -p hardware/nvidia/tegra/nv-public
    cp -r ${tegraPublicDtsSrc}/* hardware/nvidia/tegra/nv-public/
    cp -r ${nvdisplaySrc} nvdisplay
 
    mkdir $out
 
    cp -r ./* $out
  '';

  sourceRootFs = runCommand "source" { } ''
    set -x

    mkdir $out
    echo
    echo Extract Rootfs tegra Ubuntu
    tar -C $out -xf ${tegraRootfs}

  '';
  

  buildModules = stdenv.mkDerivation {
    name = "l4t-modules-${l4tVersion}";
    inherit (linux-gpuvm) version;
    src = source;

    patches = [
      ./patches/0001-build-fixes.patch
      ./patches/linux-6-6-build-fixes.patch
    ];

    postUnpack = ''
      # make kernel headers readable for the nvidia build system.
      cp -r ${linux-gpuvm.dev} linux-dev
      chmod -R u+w linux-dev

      ln -sf ../../../../../../nvethernetrm source/nvidia-oot/drivers/net/ethernet/nvidia/nvethernet/nvethernetrm

      export KERNEL_HEADERS=$(pwd)/linux-dev/lib/modules/${linux-gpuvm.modDirVersion}/build
    '';

    nativeBuildInputs = linux-gpuvm.moduleBuildDependencies ++ [ buildPackages.kmod ];
    depsBuildBuild = [ buildPackages.stdenv.cc ];

    makeFlags = [
      "ARCH=${stdenv.hostPlatform.linuxArch}"
      "INSTALL_MOD_PATH=${placeholder "out"}"
      "modules"
    ] ++ lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform) [
      "CROSS_COMPILE=${stdenv.cc}/bin/${stdenv.cc.targetPrefix}"
    ];

    CROSS_COMPILE = lib.optionalString (
      stdenv.hostPlatform != stdenv.buildPlatform
    ) "${stdenv.cc}/bin/${stdenv.cc.targetPrefix}";

    hardeningDisable = [ "pic" ];

    NIX_CFLAGS_COMPILE = "-fno-stack-protector -Wno-error=attribute-warning -I ${source}/nvidia-oot/sound/soc/tegra-virt-alt/include ${
      lib.concatMapStrings (x: "-isystem ${x} ") (kernelIncludes linux-gpuvm.dev)
    }";

    buildPhase = ''
      set -x
      echo "Building modules in phase..."
      make \
        ARCH=${stdenv.hostPlatform.linuxArch} \
        modules
    '';

    installPhase = ''
      set -x
      make \
        ARCH=${stdenv.hostPlatform.linuxArch} \
        INSTALL_MOD_PATH=$out \
        INSTALL_MOD_STRIP=1 \
        modules_install
    '';
  };

in
stdenv.mkDerivation {
  name = "ubuntu-rootfs-l4t-${l4tVersion}";
  
  inherit (linux-gpuvm) version;
  src = source;

  patches = [
    ./patches/0001-build-fixes.patch
    ./patches/linux-6-6-build-fixes.patch
  ];

  postUnpack = ''

    # make kernel headers readable for the nvidia build system.
    cp -r ${linux-gpuvm.dev} linux-dev
    chmod -R u+w linux-dev

    #chmod -R u+w ./
    ln -sf ../../../../../../nvethernetrm source/nvidia-oot/drivers/net/ethernet/nvidia/nvethernet/nvethernetrm

    #export KERNEL_OUTPUT=$(pwd)/linux-dev/lib/modules/${linux-gpuvm.modDirVersion}/build
    #export KERNEL_HEADERS=$(pwd)/linux-dev/lib/modules/${linux-gpuvm.modDirVersion}/build/source

    export KERNEL_HEADERS=$(pwd)/linux-dev/lib/modules/${linux-gpuvm.modDirVersion}/build

    echo 
    echo pwd
    pwd
    echo

    echo 
    echo ls
    ls -lah
    echo

  '';


  nativeBuildInputs = linux-gpuvm.moduleBuildDependencies ++ [ buildPackages.kmod pkgs.whois ];

  # some calls still go to `gcc` in the build
  depsBuildBuild = [ buildPackages.stdenv.cc mkpasswd fakeroot];



  makeFlags =
  [
    "ARCH=${stdenv.hostPlatform.linuxArch}"
    "INSTALL_MOD_PATH=${placeholder "out"}"
    "modules"
  ]
  ++ lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform) [
    "CROSS_COMPILE=${stdenv.cc}/bin/${stdenv.cc.targetPrefix}"
  ];


  CROSS_COMPILE = lib.optionalString (
    stdenv.hostPlatform != stdenv.buildPlatform
  ) "${stdenv.cc}/bin/${stdenv.cc.targetPrefix}";

  hardeningDisable = [ "pic" ];

  # unclear why we need to add nvidia-oot/sound/soc/tegra-virt-alt/include
  # this only happens in the nix-sandbox and not in the nix-shell
  NIX_CFLAGS_COMPILE = "-fno-stack-protector -Wno-error=attribute-warning -I ${source}/nvidia-oot/sound/soc/tegra-virt-alt/include ${
    lib.concatMapStrings (x: "-isystem ${x} ") (kernelIncludes linux-gpuvm.dev)
  }";

  buildPhase = ''true'';

  installPhase = ''
    set -x
    
    # Create temporary directory for building the rootfs
    #ROOTFS=$(mktemp -d)
    #chmod 755 $ROOTFS
    
    mkdir rootfs
    ROOTFS=$(pwd)/rootfs

    echo "Copying rootfs to temporary directory"
    cp -r ${sourceRootFs}/* $ROOTFS/
 
    #echo "Creating kernel modules directory"
    chmod -R u+w $ROOTFS
    mkdir -p $ROOTFS/lib/modules/${linux-gpuvm.modDirVersion}
    chmod -R 755 $ROOTFS/lib/modules

    echo "Copying built modules to temporary directory"
    cp -r ${buildModules}/lib/modules/${linux-gpuvm.modDirVersion}/* $ROOTFS/lib/modules/${linux-gpuvm.modDirVersion}/

    echo "Copying linux-gpuvm modules to temporary directory"
    cp -r ${linux-gpuvm}/lib/modules/${linux-gpuvm.modDirVersion}/* $ROOTFS/lib/modules/${linux-gpuvm.modDirVersion}/

    # Run depmod to generate modules.dep and map files
    depmod -b $ROOTFS -a ${linux-gpuvm.modDirVersion}

    touch $ROOTFS/root/test1.txt

    echo "hi from nix 2" >  $ROOTFS/root/test1.txt


    # Generate password hash
    HASH=$(mkpasswd -m sha-512 "root")

    # Update the root entry in shadow file
    sed -i "s|^root:[^:]*|root:$HASH|" $ROOTFS/etc/shadow


    # Add user to passwd file
    echo "ghaf:x:1000:1000:New User:/home/ghaf:/bin/bash" >> $ROOTFS/etc/passwd

    # Add group entry
    echo "ghaf:x:1000:" >> $ROOTFS/etc/group

    # Create encrypted password and add to shadow
    echo "ghaf:$(openssl passwd -6 "ghaf"):19000:0:99999:7:::" >> $ROOTFS/etc/shadow

    # Create home directory
    mkdir -p $ROOTFS/home/ghaf

    # Copy skel files if needed
    cp -r $ROOTFS/etc/skel/. $ROOTFS/home/ghaf/

    chmod 644 $ROOTFS/etc/passwd
    chmod 644 $ROOTFS/etc/group
    chmod 600 $ROOTFS/etc/shadow
    chmod 755 -R $ROOTFS/home/ghaf

    # Extract JetsonLinux to ghaf home folder
    cd $ROOTFS/root
    tar -xf ${jetsonLinux}

    # Finally, copy everything to the output directory
    mkdir -p $out

    echo Create and format image
    ${pkgs.qemu}/bin/qemu-img create -f raw $out/rootfs_ubuntu.img.raw 12G

    #chown -R root:root $ROOTFS
    #${pkgs.e2fsprogs}/bin/mkfs.ext4 -E root_owner=0:0 -d $ROOTFS/ $out/rootfs_ubuntu.img.raw

    fakeroot -- sh -c "chown -R root:root $ROOTFS && ${pkgs.e2fsprogs}/bin/mkfs.ext4 -d $ROOTFS $out/rootfs_ubuntu.img.raw"

    chmod 755 $out/rootfs_ubuntu.img.raw

    cp ${linux-gpuvm}/Image $out
  '';

  meta = with lib; {
    description = "Ubuntu rootfs for L4T ${l4tVersion}";
    platforms = [ "aarch64-linux" ];
  };
}
