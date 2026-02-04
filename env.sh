#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
nebula_root="$(cd "$(dirname "${script_dir}")" && pwd)"

export PATH=${nebula_root}/prebuilts/gcc-linaro-7.5.0-2019.12/bin:$PATH
export PATH=${nebula_root}/.jiri_root/bin:$PATH

cp -a ${script_dir}/jiri/jiri ${nebula_root}/.jiri_root/bin/

if [[ -e "/usr/share/bash-completion/completions/git" ]]; then
  source /usr/share/bash-completion/completions/git
fi

