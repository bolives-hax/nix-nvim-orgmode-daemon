
{
  pkgs,
  lib,
  languageModel
}: let
  scriptDeps = with pkgs; [
    sox
    piper-tts
    bash
  ];
  src = ./call_sip.sh;
  scriptName = "call_sip";
in pkgs.runCommand "call_sip" {
  #name = "orgmode-nvim-call";
  #src = ./call_sip.sh;
  #version = "
  #buildInputs = with pkgs; [ bash ];
  nativeBuildInputs = with pkgs; [ makeWrapper ];
  meta = {
    mainProgram = scriptName;
  };
} ''
   mkdir -p $out/{bin,share}

   cp ${languageModel}/en_US-amy-low.onnx $out/share/en_US-amy-low.onnx
   cp ${languageModel}/en_US-amy-low.onnx.json $out/share/en_US-amy-low.onnx.json

   install -m +x ${src} $out/bin/${scriptName}

   wrapProgram $out/bin/${scriptName} \
   --prefix PATH : ${lib.makeBinPath scriptDeps} \
   --set MODEL_PATH $out/share/en_US-amy-low.onnx \
   --set AUDIO_ARTIFACT_USER $USER
''
