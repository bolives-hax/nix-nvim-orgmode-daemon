{config,pkgs, lib, options,...}: {
  options.orgmodeNvimDaemon = with lib; {
    enable = lib.mkEnableOption "enable the neovim base orgmode reminder daemon";
    phoneReminder = {
      languageModelPackage = lib.mkOption {
        type = types.either types.package types.path;
      };
      staticSoundsPackage = lib.mkOption {
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
        #scriptBin = import ./sip_call.sh.nix {inherit lib pkgs ; languageModel = phoneReminder.languageModelPackage; };

    in lib.optionalAttrs enable {
      path = with pkgs; [
        #scriptBin
        bash
        # TODO V only when we can receive them in any way <DEBUG>
        libnotify

      ];
      environment = {
        # V TODO not needed for phone only headless mode
        #XDG_RUNTIME_DIR = "/run/user/1000";
        #WAYLAND_DISPLAY = "wayland-1";
        #XDG_STATE_HOME = "/run/orgmodenvimd/";
        # TODO rather use the env vars specified below
        #STATIC_SOUNDS_DIR = "/nix/store/l747zs99y5x0w987z0kxm2rx1pl14341-asterisk_custom_piper_sounds/";

        # TODO V when this is incorrect no error is being thrown and nothing happens ... also make it so
        # that config and lm can be passed separately 
        LANGUAGE_MODEL_FILE = "${config.orgmodeNvimDaemon.phoneReminder.languageModelPackage}/share/lm.onnx";
        STATIC_SOUNDS_DIR = "${config.orgmodeNvimDaemon.phoneReminder.staticSoundsPackage}/";
        AUDIO_DIR = "/var/lib/orgmodenvimd";
        CALL_TARGET = "+49202307435";
        TEMP_DIR = "/run/orgmodenvimd/";
        HOME = "/run/orgmodenvimd";
      };
      serviceConfig = {
        Type = "simple";
        # TODO 
        User = "orgmodenvimd";
        Group = "orgmodenvimd";
        SupplementaryGroups=[ "asterisk" ];
        # V do we really need to make  a script for this? maybe w can escape the "s properly!?
        ExecStart = pkgs.writeShellScript "check-tasks" ''
          ${orgmodeNvimDaemon.package}/bin/nvim  --headless -i NONE -c "lua = require('orgmode').cron()"
        '';
        RuntimeDirectory = "orgmodenvimd";
        RuntimeDirectoryMode = "0770";
        # V /var/lib
        StateDirectory = "orgmodenvimd";
        StateDirectoryMode = "0775";
        /*
            TODO ^  from https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#RuntimeDirectory=

          Directory	Below path for system units	Below path for user units	Environment variable set
          RuntimeDirectory=	/run/	$XDG_RUNTIME_DIR	$RUNTIME_DIRECTORY
          StateDirectory=	/var/lib/	$XDG_STATE_HOME	$STATE_DIRECTORY
          CacheDirectory=	/var/cache/	$XDG_CACHE_HOME	$CACHE_DIRECTORY
          LogsDirectory=	/var/log/	$XDG_STATE_HOME/log/	$LOGS_DIRECTORY
          ConfigurationDirectory=	/etc/	$XDG_CONFIG_HOME	$CONFIGURATION_DIRECTORY
        */
      };
    };
  };

}
