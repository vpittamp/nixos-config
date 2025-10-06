{ fetchzip }:

fetchzip {
  url = "https://alphacephei.com/vosk/models/vosk-model-en-us-0.22-lgraph.zip";
  sha256 = "1dl9sf36mn8l3bcxni4qwrv52hwsfmcm9j08km7iz2vhaiz5wn0r";
  # Upstream archives ship with a top-level directory already,
  # but stripping it makes the model path simpler when referenced.
  stripRoot = true;
}
