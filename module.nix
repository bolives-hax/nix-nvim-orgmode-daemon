{config,pkgs, lib, options,...}: {
  options.orgmodeNvimDaemon = with lib; {
    enable = lib.mkEnableOption "enable the neovim base orgmode reminder daemon";
    phoneReminder = {
      languageModelPackage = lib.mkOption {
        type = types.either types.package types.path;
      };
      enable = lib.mkEnableOption "send out notifications via asterisk(phone)";
    };
    package = lib.mkOption {
      type = types.package;
      #default = self.packages.x86_64-linux.neovimOrgmode = nixVim.legacyPackages.x86_64-linux.makeNixvimWithModule {
    };
    #orgModePath
  };

  disabledModules = [
      "services/networking/asterisk.nix"
  ];
  imports = [
    ./asterisk_fixperms.nix
  ];
  config = with config; with orgmodeNvimDaemon; {
    # TODO don't hardcode user
    users.groups.orgmodenvimd = {};
    users.users.orgmodenvimd = {
      isSystemUser = true;
      extraGroups = lib.optional phoneReminder.enable "asterisk";
      group = "orgmodenvimd";
    };
    systemd.timers."orgmode-nvim-daemon" = lib.optionalAttrs enable {
      enable = true;
      # TODO requiredBy or something so it gets started whenever our runlevel/system starts
      after = [
        "network.target"
                            # V don't attempt to send out reminders
                            # via phone b4 asterisk is up ...
                            # (probably would be a good idea to also schedule ) 
      ] ++ (lib.optional phoneReminder.enable "asterisk.service");
      timerConfig = {
        # every 00th second every minute -> once a minute ...
        OnCalendar = "*-*-* *:*:00";
        # V if the system was down during the event
        # still trigger it
        Persistent = true;
        #OnBootSec = "5m";
        #OnUnitActiveSec = "5m";
        Unit = "orgmode-nvim-daemon.service";
      };  
    };
    
    systemd.services."orgmode-nvim-daemon" = let
        # Use callpackage TODO 
        scriptBin = import ./sip_call.sh.nix {inherit lib pkgs ; languageModel = phoneReminder.languageModelPackage; };

    in lib.optionalAttrs enable {
      path = with pkgs; [
        scriptBin
        bash
        # TODO V only when we can receive them in any way <DEBUG>
        libnotify

      ];
      environment = {
        # V TODO not needed for phone only headless mode
        #XDG_RUNTIME_DIR = "/run/user/1000";
        #WAYLAND_DISPLAY = "wayland-1";
        #XDG_STATE_HOME = "/run/orgmodenvimd/";
        #HOME = "/run/orgmodenvimd/";
        HOME = "/tmp/n";
      };
      serviceConfig = {
        Type = "simple";
        # TODO 
        User = "orgmodenvimd";
        #Group = "asterisk";
        SupplementaryGroups=[ "asterisk" ];
        # V do we really need to make  a script for this? maybe w can escape the "s properly!?
        ExecStart = pkgs.writeShellScript "check-tasks" ''
          ${orgmodeNvimDaemon.package}/bin/nvim  --headless -i NONE -c "lua = require('orgmode').cron()"
        '';
          # V do de even need ShaDa?
          #"-i NONE
        #]);
        #RuntimeDirectory = "orgmodenvimd";
        #RuntimeDirectoryMode = "0700";
      };
    };
  };

}
