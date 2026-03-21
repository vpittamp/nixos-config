#!/usr/bin/env bash
# Import the current system clipboard into local tmux buffers.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

"$script_dir/clipboard-paste.sh" | "$script_dir/clipboard-tmux-load.sh"
