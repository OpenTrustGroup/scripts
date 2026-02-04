#!/bin/bash
# Copyright 2018 GoldenRiver Technology Co., Ltd. All rights reserved.

declare JIRI="./.jiri_root/bin/jiri"

function jiri-runp {
  ${JIRI} runp -show-name-prefix -exit-on-error $@
}

function jiri-runp-no-err {
  ${JIRI} runp -show-name-prefix $@
}

function nbl-checkout-latest {
  ${JIRI} update -gc
}

function nbl-checkout-branch {
  ${JIRI} update -gc "${release_out_dir}/snapshots/${branch_name}.xml"
  jiri-runp "git fetch origin; git checkout -f origin/${branch_name}"
}

function nbl-checkout-topic {
  nbl-checkout-latest
  ${JIRI} patch -host=http://gerrit -no-branch -topic ${gerrit_topic}
}

# Checkout source code to specific snapshot (version).
# nbl-checkout-snapshot ${sdk_snapshot}
function nbl-checkout-snapshot {
  ${JIRI} update -gc ${sdk_snapshot}
}

function nbl-full-build {
  local key_path=$1
  if [[ -z ${key_path// } ]]; then
    fx-command-run set-venus venus-hee
    fx-command-run full-build
  else
    fx-command-run set-venus venus-hee --secmgr_key_path ${key_path}
    fx-command-run full-build
  fi
}

function nbl-clean {
  rm -fr ${FUCHSIA_OUT_DIR}
}

function nbl-clean-build {
  fx-command-run clean-build-venus venus-hee
}

function nbl-qemu-tests {
  local count
  local cmds
  echo "run_venus_args=${run_venus_args}"

  IFS=';' read -r -a cmds<<< "${run_venus_args}"
  count=${#cmds[@]}
  for ((i=0; i<${count}; i++));
  do
    echo "cmd ${i}: ${cmds[$i]}"
    FUCHSIA_IP_SUBNET_PREFIX=192.168.200 TERM=xterm ./scripts/fx run-venus ${cmds[$i]}
  done

}

#####################################################################
#### nbl-make APIs
#####################################################################
function nbl-make-snapshot {
  local snapshots_dir="${release_out_dir}/snapshots"
  mkdir -p ${snapshots_dir}
  ${JIRI} snapshot "${snapshots_dir}/${tag_name}.xml"
  pushd "${snapshots_dir}"
  sha1sum "${tag_name}.xml" > "${tag_name}.xml.sha1"
  popd
}

function nbl-make-gittag {
  if [[ $release_type =~ internal|official ]]; then
    jiri-runp "git tag -f -a ${tag_name} -m ${version_time}"
  fi
}

function nbl-make-sdk {
  local sdk_path="${FUCHSIA_OUT_DIR}/_release/${sdk_version}"
  sdk_options+=" -o ${sdk_path}"
  [[ -d "${sdk_path}" ]] && rm -rf ${sdk_path}
  fx-command-run make-sdk ${sdk_options}
  nbl-make-sha1-by-dir "${sdk_path}"
  nbl-compress-sdk "${sdk_path}"
}

# Create sha1 for each files
function nbl-make-sha1-files {
  pushd $1
  find . -type f -exec sha1sum {} > $(basename $1).sha1 \;
  popd
}

# Create sha1 of all files under sdk path and output to file ${sdk_version}.sha1.
# nbl-make-sha1-by-dir ${sdk_path}
function nbl-make-sha1-by-dir {
  pushd "${1}"
  find ./ -type f | sort | xargs sha1sum > $(basename ${1}).sha1
  popd
}

# Compress sdk files to *.tar.gz, and create sha1 of .tar.gz for verification.
# nbl-compress-sdk ${sdk_path}
function nbl-compress-sdk {
  local work_dir="$(dirname ${1})"
  local sdk_tgz="$(basename ${1})${sdktgz_suffix}.tar.gz"
  local sdk_dir="$(basename ${1})"
  pushd "${work_dir}"
  tar -czf "${sdk_tgz}" "${sdk_dir}"
  sha1sum "${sdk_tgz}" > "${sdk_tgz}.sha1"
  popd
}

function nbl-make-pdk {
  local pdk_path="${FUCHSIA_OUT_DIR}/_release/${pdk_version}"
  pdk_options="-o ${pdk_path}"
  [[ -d "${pdk_path}" ]] && rm -rf ${pdk_path}
  fx-command-run make-pdk ${pdk_options}
  nbl-make-sha1-by-dir "${pdk_path}"
  nbl-compress-pdk "${pdk_path}"
}

function nbl-make-linux-patch {
  local linux_patch_path="${FUCHSIA_OUT_DIR}/_release/${linux_patch_version}"
  linux_patch_options="-o ${linux_patch_path}"
  [[ -d "${linux_patch_path}" ]] && rm -rf ${linux_patch_path}
  fx-command-run make-linux-patch ${linux_patch_options}
  nbl-make-sha1-by-dir "${linux_patch_path}"
  nbl-compress-linux-patch "${linux_patch_path}"
}

function nbl-compress-pdk {
  local work_dir="$(dirname ${1})"
  local pdk_tgz="$(basename ${1}).tar.gz"
  local pdk_dir="$(basename ${1})"
  pushd "${work_dir}"
  tar -czf "${pdk_tgz}" "${pdk_dir}"
  sha1sum "${pdk_tgz}" > "${pdk_tgz}.sha1"
  popd
}

function nbl-compress-linux-patch {
  local work_dir="$(dirname ${1})"
  local linux_patch_tgz="$(basename ${1}).tar.gz"
  local linux_patch_dir="$(basename ${1})"
  pushd "${work_dir}"
  tar -czf "${linux_patch_tgz}" "${linux_patch_dir}"
  sha1sum "${linux_patch_tgz}" > "${linux_patch_tgz}.sha1"
  popd
}

#####################################################################
#### nbl-upload APIs
#####################################################################
function nbl-upload-targets {
  [[ -z "${upload_args}" ]] && return 0

  IFS=';' read -r -a args <<< "${upload_args}"

  for arg in ${args[@]}; do
    IFS=':' read -r -a tmp <<< "${arg}"
    local target=${tmp[0]}
    local method=${tmp[1]}
    eval nbl-upload-${target}-${method} "${tmp[@]:2}"
  done
}

# Upload sdk to remote server thru rsync/ssh and expect.
# nbl-upload-sdk-rsync ${ssh_server} ${ssh_passwd} ${ssh_rpath}
function nbl-upload-sdk-rsync {
  local sdk_tgz="${sdk_version}${sdktgz_suffix}.tar.gz"
  local pdk_tgz="${pdk_version}.tar.gz"
  local linux_patch_tgz="${linux_patch_version}.tar.gz"
  local server="${1}"
  local passwd="${2}"
  local rpath="${3}"
  pushd "${FUCHSIA_OUT_DIR}"
  cat > upload-sdk.exp << EOF
#!/usr/bin/expect -f
set timeout -1
spawn sh -c "rsync --partial --progress --rsh=ssh ${sdk_tgz}* ${pdk_tgz}* ${server}:${rpath}"
expect {
    "Are you sure you want to continue connecting (yes/no)? " {
        send "yes\r"
        exp_continue
    }
    "${server}'s password: "
}
send "${passwd}\r"
expect "$ "
spawn sh -c "ssh ${server} 'cd ${rpath} && sha1sum -c ${sdk_tgz}.sha1'"
expect "${server}'s password: "
send "${passwd}\r"
set timeout 30
expect {
    timeout {
        puts "sha1 check timeout !!!"
        exit 1
    }
    "*: FAILED" {
        exit 1
    }
    "${sdk_tgz}: OK"
}
expect "$ "
EOF
  expect upload-sdk.exp
  popd
}

function nbl-upload-snapshot-scp {
  local snapshot_xml="${tag_name}.xml"
  local server="${1}"
  local passwd="${2}"
  local rpath="${3}"
  local snapshots_dir="${release_out_dir}/snapshots"

  if [[ $release_type = "internal" || $release_type = "official" ]]; then
    pushd "${snapshots_dir}"
    scp ${snapshot_xml}* ${server}:${rpath}
    popd
  fi
}

function nbl-upload-snapshot-pwdscp {
  local snapshot_xml="${sdk_version}.xml"
  local server="${1}"
  local passwd="${2}"
  local rpath="${3}"
  pushd "${FUCHSIA_OUT_DIR}/_snapshot"
  cat > upload-snapshot.exp << EOF
#!/usr/bin/expect -f
set timeout -1
spawn sh -c "scp ${snapshot_xml}* ${server}:${rpath}"
expect {
    "Are you sure you want to continue connecting (yes/no)? " {
        send "yes\r"
        exp_continue
    }
    "${server}'s password: "
}
send "${passwd}\r"
expect "$ "
spawn sh -c "ssh ${server} 'cd ${rpath} && sha1sum -c ${snapshot_xml}.sha1'"
expect "${server}'s password: "
send "${passwd}\r"
set timeout 30
expect {
    timeout {
        puts "sha1 check timeout !!!"
        exit 1
    }
    "*: FAILED" {
        exit 1
    }
    "${snapshot_xml}: OK"
}
expect "$ "
EOF
  expect upload-snapshot.exp
  popd
}

function nbl-upload-gittag-ssh {
  if [[ $release_type = "internal" || $release_type = "official" ]]; then
    jiri-runp "git push origin refs/tags/${tag_name} -f"
  fi
}

function nbl-make-changelist {
  local out_dir=$1
  local fname="${out_dir}/$(basename ${out_dir})-changelist.txt"

  rm -f ${fname}

  if [[ $release_type = "developer" ]]; then
    jiri-runp-no-err "git log --oneline ${last_tag_name}..HEAD" | tee ${fname}
  else
    jiri-runp-no-err "git log --oneline ${last_tag_name}..${tag_name}" | tee ${fname}
  fi
}
