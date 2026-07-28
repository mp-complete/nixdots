{ pkgs, ... }:
{
  # KVM display-disconnect resilience.
  #
  # euler's two monitors hang off a KVM switch. When the KVM points at another
  # machine it drops HPD on DP-1/DP-2, so nvidia-drm marks the connectors
  # "disconnected" and tears down the DRM outputs. niri then destroys the
  # corresponding wl_output globals, and Wayland clients that watch outputs —
  # notably Steam (CEF/Chromium) and running games (swapchain loss) — crash.
  #
  # Fix: pin a saved EDID onto each connector and force it enabled, so the
  # output survives the KVM switching away and the compositor never loses it.
  # This uses NixOS's hardware.display module, which emits the matching
  #   video=<out>:e  and  drm.edid_firmware=<out>:edid/<file>
  # kernel params plus installs the EDID blobs as firmware.
  #
  # EDID blobs were captured from this exact hardware via
  #   cat /sys/class/drm/card1-DP-1/edid > dp1-side-asus-vg27a.bin
  #   cat /sys/class/drm/card1-DP-2/edid > dp2-main-viewsonic-vx3276.bin
  # Re-capture and replace if the monitors are swapped.
  #
  # NOTE: the NVIDIA proprietary driver's support for forced EDID/mode on KMS
  # connectors is imperfect; if a KVM switch still drops an output after this,
  # a hardware EDID emulator ("headless"/dummy dongle) on the KVM is the
  # bulletproof fallback.
  hardware.display = {
    edid.packages = [
      (pkgs.runCommand "euler-edid" { } ''
        mkdir -p "$out/lib/firmware/edid"
        cp ${./edid/dp1-side-asus-vg27a.bin} "$out/lib/firmware/edid/euler-dp1.bin"
        cp ${./edid/dp2-main-viewsonic-vx3276.bin} "$out/lib/firmware/edid/euler-dp2.bin"
      '')
    ];
    outputs = {
      # DP-1 — ASUS VG27A (side / portrait)
      "DP-1" = {
        edid = "euler-dp1.bin";
        mode = "e";
      };
      # DP-2 — ViewSonic VX3276-QHD (main)
      "DP-2" = {
        edid = "euler-dp2.bin";
        mode = "e";
      };
    };
  };
}
