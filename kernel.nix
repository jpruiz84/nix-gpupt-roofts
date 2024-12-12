{ lib
, pkgs
, stdenv
, fetchgit
, buildLinux
, applyPatches
, fetchpatch
, crossSystem ? null
, ... } @ args:

let
  isNative = pkgs.stdenv.isAarch64;
  pkgsAarch64 = if isNative then pkgs else pkgs.pkgsCross.aarch64-multiplatform;

  kernelVersion = "6.6.59";

in
{
  linux-gpuvm = buildLinux (args // {
  version = kernelVersion;
  extraMeta.branch = "6.6";

  # defconfig = "defconfig";

  src = applyPatches {
      src = fetchgit {
        url = "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git";
        hash = "sha256-SSTZ5I+zhO3horHy9ISSXQdeIWrkkU5uMlbQVnB5zxY=";
        rev = "v${kernelVersion}";
      };

      patches = [

        (fetchpatch {
          name = "memory: tegra: Add Tegra234 clients for RCE and VI";
          url = "https://github.com/torvalds/linux/commit/9def28f3b8634e4f1fa92a77ccb65fbd2d03af34.patch";
          hash = "sha256-WZwKGL0kPZ3SxwdW3oi7Z3Tc0BMuuOuL9/HlLzg73q8=";
        })

        (fetchpatch {
          name = "hwmon: (ina3221) Add support for channel summation disable";
          url = "https://github.com/torvalds/linux/commit/7b64906c98fe503338066b97d3ff2dad65debf2b.patch";
          hash = "sha256-SB2zipFoJQsOjuKUFV8W1PBi8J8qTgdZcuPI3lNvGuA=";
        })

        (fetchpatch {
          name = "cpufreq: tegra194: save CPU data to avoid repeated SMP calls";
          url = "https://github.com/torvalds/linux/commit/6b121b4cf7e1f598beecf592d6184126b46eca46.patch";
          hash = "sha256-/v73qEkT3nrdzMDQZCbSMeacLSgj5aZTwnhvM1lFd+w=";
        })

        (fetchpatch {
          name = "cpufreq: tegra194: use refclk delta based loop instead of udelay";
          url = "https://github.com/torvalds/linux/commit/a60a556788752a5696960ed11409a552b79e68e8.patch";
          hash = "sha256-ZvogH5F3dUGHVXcpqhxbDah1Llc13J7SOYVVbJpstTw=";
        })

        (fetchpatch {
          name = "cpufreq: tegra194: remove redundant AND with cpu_online_mask";
          url = "https://github.com/torvalds/linux/commit/c12f0d0ffade589599a43b0d0f0965579ca80f76.patch";
          hash = "sha256-iiW20hwMQS/B6F1I3O5KwMdIVYrdOwSPzKrB5juaxMY=";
        })

        (fetchpatch {
          name = "fbdev/simplefb: Support memory-region property";
          url = "https://github.com/torvalds/linux/commit/8ddfc01ace51c85a2333fb9a9cbea34d9f87885d.patch";
          hash = "sha256-rMk0BIjOsc21HFF6Wx4pngnldp/LB0ODbUFGRDjtsUw=";
        })

        (fetchpatch {
          name = "fbdev/simplefb: Add support for generic power-domains";
          url = "https://github.com/torvalds/linux/commit/92a511a568e44cf11681a2223cae4d576a1a515d.patch";
          hash = "sha256-GOo7OLQObixVEKguiEzp1xLMlqE0QMQVhx8ygwkNb9M=";
        })

      ];
      # Remove device tree overlays with some incorrect "remote-endpoint" nodes.
      # They are strings, but should be phandles. Otherwise, it fails to compile
      # postPatch = ''
      #   rm \
      #     nvidia/platform/t19x/galen/kernel-dts/tegra194-p2822-camera-imx185-overlay.dts \
      #     nvidia/platform/t19x/galen/kernel-dts/tegra194-p2822-camera-dual-imx274-overlay.dts \
      #     nvidia/platform/t23x/concord/kernel-dts/tegra234-p3737-camera-imx185-overlay.dts \
      #     nvidia/platform/t23x/concord/kernel-dts/tegra234-p3737-camera-dual-imx274-overlay.dts
      #
      #   sed -i -e '/imx185-overlay/d' -e '/imx274-overlay/d' \
      #     nvidia/platform/t19x/galen/kernel-dts/Makefile \
      #     nvidia/platform/t23x/concord/kernel-dts/Makefile
      #
      # '' + lib.optionalString realtime ''
      #   for p in $(find $PWD/rt-patches -name \*.patch -type f | sort); do
      #     echo "Applying $p"
      #     patch -s -p1 < $p
      #   done
      # '';
    };

    autoModules = false;
    features = { }; # TODO: Why is this needed in nixpkgs master (but not NixOS 22.05)?
    kernelPatches = [
      {
        name = "Vfio_platform Reset Required False";
        patch = ./patches/0002-vfio_platform-reset-required-false.patch;
      }
      {
        name = "Add bpmp-virt modules";
        patch = ./patches/0001-Add-bpmp-virt-modules.patch;
      }
      {
        name = "Bpmp-host: allows all domains";
        patch = ./patches/0002-Bpmp-host-allows-all-domains.patch;
      }
    ];

    structuredExtraConfig = with lib.kernel; {
      # Platform-dependent options for mainline kernel
      ARM64_PMEM = yes;
      PCIE_TEGRA194 = yes;
      PCIE_TEGRA194_HOST = yes;
      BLK_DEV_NVME = yes;
      NVME_CORE = yes;
      FB_SIMPLE = yes;
      TEGRA_BPMP_GUEST_PROXY = yes;
    };

    # kernelPatches = [
    # {
    #   name = "make-USB_XHCI_TEGRA-builtins";
    #   patch = null;
    #   extraConfig = ''
    #     ARM64_PMEM y
    #     PCIE_TEGRA194 y
    #     PCIE_TEGRA194_HOST y
    #     BLK_DEV_NVME y
    #     NVME_CORE y
    #     FB_SIMPLE y
    #     RTW88 y
    #     RTW88_8822CE y
    #     TEGRA_BPMP_GUEST_PROXY y
    #     TEGRA_BPMP_HOST_PROXY y
    #   '';
    # }
    # ];

  });
}
