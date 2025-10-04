{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    orgmodeSrc = {
      url = "github:bolives-hax/orgmode/orgmode_force_count_hacks";
      flake = false;
    };
    nixVim = {
      url = "github:nix-community/nixvim";
    };
    languageModel = {
      url = "path:/tmp/lm";
      flake = false;
    };
  };


  outputs = {self,nixpkgs,orgmodeSrc,nixVim,languageModel}: {
    nixosConfigurations.t = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        { boot.isContainer = true; }
        self.nixosModules.orgmodeNeovimDaemon
      ];
    };
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
    nixosModules.default  = self.nixosModules.orgmodeNeovimDaemon;
    nixosModules.orgmodeNeovimDaemon = {pkgs,...}: {
      imports = [
        ./module.nix
      ];
      orgmodeNvimDaemon = {
        enable = true;
        # TODO less ghetto + generic name so you can switch/use multiple
        phoneReminder = {
          enable = true;
          languageModelPackage = "${languageModel}";
        };
        package = nixVim.legacyPackages.x86_64-linux.makeNixvimWithModule {
          module = {
            imports = [
              self.nixvimModules.default
            ];
            plugins.orgmode.settings = {
              org_agenda_files = "/tmp/flandre/orgfiles/**/*";
              org_default_notes_file = "/tmp/flandre/orgfiles/refile.org";
            };
          };
        };
      };
      #nvimOrgmodeDaemon = {
      #    module = {
      #    };
      #  };  
      #};
    };#

    #nixvimModules.neovimOrgmodeNotifier
    nixvimModules.default = {config,lib,pkgs,...}: let
      in {
        nixpkgs.overlays = [ self.overlays.default ];
        extraPackages = with pkgs; [
          sox
          piper-tts
        ];
        extraPackagesAfter = with pkgs;[
          # needed so it can send notifications to e.g sway
          # TODO remove this 
          libnotify
        ];

        /*extraPlugins = with pkgs.vimPlugins; [
          orgmode
        ];*/

        # TODO strip down the size of neovim by omitting
        # stuff we don't need like ruby ig

        plugins.orgmode = {
          enable = true;
          package = pkgs.vimPlugins.orgmode;
          settings = {
            notifications = {
              enabled = false;
              cron_enabled = true;
      #-- will send notif 1 and 5 min before deadline
      #-- can be called via nvim --headless -c 'lua require("orgmode").cron()'
      #-- ensure that notify-send is in PATH of nvim and working properly!!!
              reminder_time = [ 0 ];
              cron_notifier = let
                f = pkgs.writeText "cron.lua" ''
                  call_utils = dofile("${./gen_callfile.lua}")
		  local perform_task_call = dofile("${./perform_task_call.lua}")

                  ${builtins.readFile ./custom_orgmode_setup.lua}
                '';
              in lib.nixvim.utils.mkRaw "dofile('${f}')";
            };
          };
          
        };

        #extraConfigLua = builtins.readFile ./custom_orgmode_setup.lua;
      };

    packages.x86_64-linux.neovimOrgmode = nixVim.legacyPackages.x86_64-linux.makeNixvimWithModule {
      module = {
        imports = [
          self.nixvimModules.default
        ];
        plugins.orgmode.settings = {
            org_agenda_files = "~/orgfiles/**/*";
            org_default_notes_file = "~/orgfiles/refile.org";
        };
      };
    };
  };

}
