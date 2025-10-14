#!/usr/bin/env bash
# Color diagnostic script for iTerm2 + tmux + Starship

echo "=== Terminal Color Diagnostics ==="
echo ""

echo "Environment Variables:"
echo "TERM: $TERM"
echo "COLORTERM: $COLORTERM"
echo "TMUX: ${TMUX:-not set}"
echo "LC_TERMINAL: ${LC_TERMINAL:-not set}"
echo ""

echo "Terminal Capabilities:"
tput colors 2>/dev/null && echo "tput colors: $(tput colors)" || echo "tput colors: not available"
echo ""

echo "=== ANSI Color Test (16 colors) ==="
for i in {0..15}; do
  printf "\e[48;5;${i}m  \e[0m"
  [ $(( (i+1) % 8 )) -eq 0 ] && echo
done
echo ""

echo "=== 256 Color Test (sample) ==="
for i in {16..231..43}; do
  printf "\e[48;5;${i}m  \e[0m"
done
echo -e "\n"

echo "=== RGB/True Color Test ==="
printf "\e[38;2;255;0;0mRed RGB\e[0m "
printf "\e[38;2;0;255;0mGreen RGB\e[0m "
printf "\e[38;2;0;0;255mBlue RGB\e[0m "
printf "\e[38;2;255;255;0mYellow RGB\e[0m "
printf "\e[38;2;255;0;255mMagenta RGB\e[0m "
printf "\e[38;2;0;255;255mCyan RGB\e[0m\n"
echo ""

echo "=== Catppuccin Mocha Color Test ==="
printf "\e[38;2;245;224;220mrosewater\e[0m "
printf "\e[38;2;242;205;205mflamingo\e[0m "
printf "\e[38;2;245;194;231mpink\e[0m "
printf "\e[38;2;203;166;247mmauve\e[0m "
printf "\e[38;2;243;139;168mred\e[0m "
printf "\e[38;2;235;160;172mmaroon\e[0m\n"
printf "\e[38;2;250;179;135mpeach\e[0m "
printf "\e[38;2;249;226;175myellow\e[0m "
printf "\e[38;2;166;227;161mgreen\e[0m "
printf "\e[38;2;148;226;213mteal\e[0m "
printf "\e[38;2;137;220;235msky\e[0m "
printf "\e[38;2;116;199;236msapphire\e[0m\n"
printf "\e[38;2;137;180;250mblue\e[0m "
printf "\e[38;2;180;190;254mlavender\e[0m\n"
echo ""

echo "=== Starship Prompt Test ==="
starship prompt 2>/dev/null || echo "Starship not available in PATH"
