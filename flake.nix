{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/master"; #nixpkgs-unstable";
    orgmodeSrc = {
      url = "github:bolives-hax/orgmode/orgmode_force_count_hacks";
      flake = false;
    };
    nixVim = {
      url = "github:nix-community/nixvim";
    };

    languageModelData = {
      url = "https://huggingface.co/csukuangfj/vits-piper-en_US-amy-low/resolve/main/en_US-amy-low.onnx";
      flake = false;
    };
    languageModelConfig = {
      url = "https://huggingface.co/csukuangfj/vits-piper-en_US-amy-low/resolve/main/en_US-amy-low.onnx.json";
      flake = false;
    };

    temporaryHackWavs = {
      url = "tarball+https://files.catbox.moe/m6nxtl.gz";
      flake = false;
    };
    
  };


  outputs = {self,nixpkgs,orgmodeSrc,nixVim,languageModelData,languageModelConfig, temporaryHackWavs}: let
    systems = nixpkgs.lib.systems.flakeExposed;
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
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
        { 
          users.users.orgmodenvimd.packages = [
            (nixVim.legacyPackages."${pkgs.system}".makeNixvimWithModule {
              module = {
                imports = [
                  self.nixvimModules.default
                ];
                plugins.orgmode.settings = {
                  org_agenda_files = "/tmp/flandre/orgfiles/**/*";
                  org_default_notes_file = "/tmp/flandre/orgfiles/refile.org";
                };
              };
            })
          ];
        }
      ];
      orgmodeNvimDaemon = {
        enable = true;
        # TODO less ghetto + generic name so you can switch/use multiple
        phoneReminder = {
          enable = true;
          languageModelPackage = self.packages.${pkgs.system}.languageModel;
          staticSoundsPackage = self.packages.${pkgs.system}.staticSounds;
        };
        package = nixVim.legacyPackages."${pkgs.system}".makeNixvimWithModule {
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
          (piper-tts.override {
            withTrain = false;
            withHTTP = false;
          })
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
              # V ensure this is set to 0 !!! as the default is false, if you do not
              # notifications.repeater_reminder_time  at:
              # https://github.com/nvim-orgmode/orgmode/blob/03777caca5c2df4c5b2067734b7829e9df07a423/lua/orgmode/notifications/init.lua#L144C6-L144C43
              # will not trigger and thus we lose re-occuring reminders
              repeater_reminder_time = [ 0 ];
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

packages = forAllSystems (system: let
  pkgs = import nixpkgs {
    inherit system;
    overlays = [
      (super: self: {
        piper-tts = self.piper-tts.override {
          withTrain = false;
          withHTTP = false;
        };
      })
    ];
  };
in {
    languageModel = pkgs.stdenv.mkDerivation {
      name = "onnx-language-model";
      phases = [ "installPhase" ];
      installPhase = ''
        mkdir -p $out/share/
        install -m 0444 ${languageModelData}  $out/share/lm.onnx
        install -m 0444 ${languageModelConfig} $out/share/lm.onnx.json
      '';
    };
    neovimOrgmode = nixVim.legacyPackages.${pkgs.system}.makeNixvimWithModule {
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
    # TODO   V this is cursed as atm piper-tts can't be used from within a
    #     build (ON aarch64) as it tries to read /proc | sysfs cpuinfo which doesn't 
    #     work
    #     from within the sandbox ... so until thats fixed im making the horrible chioce
    #     to just import a tarball ive build on x86 (since its not executables its
    #     not as bad as using binaries esp dynamic ones ... don't judge lol
    # TODO V use callPackage
    staticSounds = /*import ./sounds/derivation.nix {
      inherit pkgs;
      languageModel = self.packages.${system}.languageModel;
      };*/ pkgs.stdenv.mkDerivation {
        name = "static-sounds-hack";
        phases = [ "unpackPhase" "installPhase" ];
        src = temporaryHackWavs;
        #buildPhase = ''
        #  cp ${temporaryHackWavs} a.tar.gz
        #'';
        installPhase = ''
          mkdir -p $out
          install -m 0444 $src/*.wav -t $out
        '';
      };
  });
};

}
