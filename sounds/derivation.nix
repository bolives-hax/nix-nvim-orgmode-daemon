# TODO use callPackage
{pkgs}: pkgs.stdenv.mkDerivation {
      name = "asterisk_custom_piper_sounds";
      #src = ./.;
      phases = [ "buildPhase" "installPhase" ];
      nativeBuildInputs = with pkgs; [
        piper-tts
        sox
        bash
      ];
      buildPhase = pkgs.writeShellScript "builder" ''
        # TODO use the same drv we defined in ./module.nix
        #export MODEL_PATH=${languageModelData}/lm.onnx
        #MODEL_CONFIG_PATH=${languageModelConfig}/lm.onnx.json

        export MODEL_PATH=${languageModelData}
        MODEL_CONFIG_PATH=${languageModelConfig}

        mkdir sounds
        SOUNDS_DIR=./sounds
        ${builtins.readFile ./gen.sh}

        # V overwrite with my nonfree cuz more aesthetic
        sox -t wavpcm ${./goodbye.wav} -r 8000 -c 1 -b 16 "''${SOUNDS_DIR}/goodbye.wav"
 
      '';
      # TODO use install command to do all in one
      installPhase = ''
        mkdir -p $out
        mv ./sounds/* $out
        chmod 444 $out/*
      '';
}
