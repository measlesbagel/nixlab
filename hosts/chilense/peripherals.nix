{ pkgs, ... }:
{
  # uaccess only takes effect before 73-seat-late.rules, and extraRules
  # lands in 99-local.rules.
  services.udev.packages = [
    (pkgs.writeTextDir "lib/udev/rules.d/70-chilense-peripherals.rules" ''
      # VIA configures the Rainy75 keyboard over WebHID.
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="320f", ATTRS{idProduct}=="5055", TAG+="uaccess"
      # mtkclient talks to MediaTek phones in BROM mode.
      SUBSYSTEM=="usb", ATTR{idVendor}=="0e8d", TAG+="uaccess"
    '')
  ];

  services.pipewire.wireplumber.extraConfig."51-maxwell-mic" = {
    "monitor.alsa.rules" = [
      {
        matches = [
          {
            "node.name" = "alsa_input.usb-Audeze_LLC_Audeze_Maxwell_Dongle_0000000000000000-01.mono-fallback";
          }
        ];
        actions.update-props."session.suspend-timeout-seconds" = 0;
      }
    ];
  };
}
