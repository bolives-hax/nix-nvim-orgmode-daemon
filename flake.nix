{
  inputs = {
    #nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    orgmodeSrc = {
      url = "github:bolives-hax/orgmode/orgmode_force_count_hacks";
      flake = false;
    };
    nixVim = {
      url = "github:nix-community/nixvim";
    };
  };


  outputs = {self,orgmodeSrc,nixVim}: {
    overlays.default = final: prev: {
      # V vimPlugins doens't respect what we do
      # here as it seems
      #lua = prev.lua.override {
      #  packageOverrides = luaself: luaprev: {
      #    orgmode = luaprev.orgmode.overrideAttrs(_: {
      #      src = "${./orgmode_fork}";
      #    });
      #  };
      #};
      #
      #
      #  the // overrides whatever comes last
      #                            V
      vimPlugins = prev.vimPlugins // {
        # todo lib's overrideExisting may be more clean or whatever
        orgmode = prev.vimPlugins.orgmode.overrideAttrs(_: {
          src = orgmodeSrc;
        });
      };
    };
    nixosModules.default  = self.ghettoOrcmodeDaemon;
    nixosModules.ghettoOrcmodeDaemon = {pkgs,...}: {
      nixpkgs.overlays = [self.overlays.default];
      imports = [
        #./module.nix
      ];
    };

    #nixvimModules.neovimOrgmodeNotifier
    nixvimModules.default = {config,lib,pkgs,...}: let
      in {
        nixpkgs.overlays = [ self.overlays.default ];
        extraPackages = with pkgs;[
          # needed so it can send notifications to e.g sway
          # TODO remove this 
          notifymuch
        ];

        /*extraPlugins = with pkgs.vimPlugins; [
          orgmode
        ];*/

        plugins.orgmode = {
          enable = true;
          package = pkgs.vimPlugins.orgmode;
          settings = {
            org_agenda_files = "~/orgfiles/**/*";
            org_default_notes_file = "~/orgfiles/refile.org";
            notifications = {
              enabled = false;
              cron_enabled = true;
      #-- will send notif 1 and 5 min before deadline
      #-- can be called via nvim --headless -c 'lua require("orgmode").cron()'
      #-- ensure that notify-send is in PATH of nvim and working properly!!!
              reminder_time = [ 0 ];
              cron_notifier = lib.nixvim.utils.mkRaw "dofile('${./custom_orgmode_setup.lua}')";
            };
          };
          
        };

        #extraConfigLua = builtins.readFile ./custom_orgmode_setup.lua;
      };

    packages.x86_64-linux.neovimOrgmodeDaemon = nixVim.legacyPackages.x86_64-linux.makeNixvimWithModule {
      module = self.nixvimModules.default;
    };
  };

}
