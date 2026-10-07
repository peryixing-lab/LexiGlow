#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
deveco_dir="${DEVECO_STUDIO_HOME:-/Applications/DevEco-Studio.app/Contents}"
export JAVA_HOME="$deveco_dir/jbr/Contents/Home"
export PATH="$deveco_dir/tools/node/bin:$JAVA_HOME/bin:$PATH"
export DEVECO_SDK_HOME="$deveco_dir/sdk"
cd "$project_dir"
"$deveco_dir/tools/node/bin/node" "$deveco_dir/tools/hvigor/bin/hvigorw.js" assembleHap --mode module -p product=default -p module=entry@default -p buildMode=debug --no-daemon "$@"
