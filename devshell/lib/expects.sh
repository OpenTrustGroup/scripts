# Copyright 2018 GoldenRiver Technology Co., Ltd. All rights reserved.
# Copyright 2017 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

if [[ -n "${ZSH_VERSION}" ]]; then
  devshell_lib_dir=${${(%):-%x}:a:h}
else
  devshell_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

readonly EXPECTS_DIR="$(dirname "${devshell_lib_dir}")/expects"
unset devshell_lib_dir

declare FINAL_EXPECT_SCRIPT=""
readonly HEE_PROMPT_CHECK="${EXPECTS_DIR}/boot/HEE-PROMPT.exp"
readonly REE_PROMPT_CHECK="${EXPECTS_DIR}/boot/REE-PROMPT.exp"

# expect-init ${FINAL_EXPECT_SCRIPT_NAME} ${QEMU_HEE_PORT} ${QEMU_TEE_PORT} ${QEMU_REE_PORT} ${QEMU_TEE_SYSTEM_MODE} ${QEMU_ACTIVE_HYP}
function expect-init {
  FINAL_EXPECT_SCRIPT="${1}"
cat > "${FINAL_EXPECT_SCRIPT}" << EOF
#!/usr/bin/expect -f

set NBL_SDK_PATH "$NBL_SDK_PATH"
set QEMU_TEE_SYSTEM_MODE ${5}
# "on": the SOS is a guest of the HEE's VMM (run-venus -z), see sos_attach
set QEMU_ACTIVE_HYP "${6:-off}"

proc printf arg {
    puts -nonewline "\[[clock format [clock seconds] -format %H:%M:%S]\] ([pid]) QEMU-${JOB} \$arg"
    flush stdout
}

proc formatTimeInterval {intervalMilliSeconds} {
    # *Assume* that the interval is positive
    set ms [expr {\$intervalMilliSeconds % 1000}]
    set i [expr {\$intervalMilliSeconds / 1000}]
    set s [expr {\$i % 60}]
    set i [expr {\$i / 60}]
    set m [expr {\$i % 60}]
    set i [expr {\$i / 60}]
    set h [expr {\$i % 24}]
    set d [expr {\$i / 24}]
    return [format "%02dm%02ds.%03d" \$m \$s \$ms]
}

proc connect_to_world {world mypid} {
    set port [expr {54000 + (\$mypid % 1000)}]
    if { \$world eq "tee" } {
        set port [expr {\$port + 1}]
    }
    if { \$world eq "ree" } {
        set port [expr {\$port + 2}]
    }
    set port_found 0
    while {\$port_found != 1} {
        spawn sh -c "${SOC_TERM_BIN} -ts \$port 2>&1 | tee serial-\$world-\$mypid.log"
        set spid \$spawn_id
        set timeout 3
        expect {
            timeout {
                printf "serial-\$world-\$mypid:\$port connected...\n"
                set port_found 1
            }
            -i \$spid "soc_term: bind: Address already in use" {
                incr port
            }
        }
    }
    set ret(spid) \$spid
    set ret(port) \$port
    return [array get ret]
}

# With an active hypervisor (run-venus -z) the SOS is a guest of the HEE's
# VMM: its kernel log (console=vmlog-sink0) goes to the HEE debuglog, as
# [VM:n] lines on the HEE serial port, and its shell runs on hvc0, the VMM's
# virtio-console, which \`vmm shell\` on the HEE console attaches to (Ctrl-D
# detaches). The REE serial port stays silent.
#
# vmm shell passes on one key per poll of its input and holds back what
# arrives at once until the next key: type into it slowly (send -s).
set send_slow {1 .05}

# Attach the HEE console to the SOS shell: 1 at its prompt, 0 on timeout.
proc sos_attach {hee secs} {
    set deadline [expr {[clock seconds] + \$secs}]
    set attached 0
    while {!\$attached && [clock seconds] < \$deadline} {
        send -i \$hee "vmm shell\r"
        set timeout 10
        expect {
            -i \$hee "controller->GetConsole" { set attached 1 }
            -i \$hee "Failed to connect VM" { expect -i \$hee "\$ "; sleep 2 }
            -i \$hee timeout { }
        }
    }
    if {!\$attached} { return 0 }
    # busybox init asks for Enter on hvc0 once the SOS reaches user space
    while {[clock seconds] < \$deadline} {
        sleep 1
        send -s -i \$hee "\r"
        set timeout 10
        expect {
            -i \$hee "Kernel panic" { printf "Linux kernel panic !!!\n"; exit 1 }
            -i \$hee "Please press Enter to activate this console. " { exp_continue }
            -i \$hee "root@FVP:/ " { return 1 }
            -i \$hee timeout { }
        }
    }
    return 0
}

# Detach the HEE console from the SOS shell, back to the HEE shell.
proc sos_detach {hee} {
    send -i \$hee "\x04"
    set timeout 15
    expect {
        -i \$hee timeout {
            printf "Venus: leaving the SOS console TIMEOUT !!!\n"
            exit 1
        }
        -i \$hee "\$ "
    }
}

set mypid [pid]
set send_human {.5 .5 1 .05 .1}

# Disable echoing of guest output
log_user 0
# Save guest console output to a file
log_file -a -noappend "serial-qemu-\$mypid.log"
printf "starting...\n"

array set hee_data [connect_to_world hee \$mypid]
set hee \$hee_data(spid)
set hee_port \$hee_data(port)

array set tee_data [connect_to_world tee \$mypid]
set tee \$tee_data(spid)
set tee_port \$tee_data(port)

array set ree_data [connect_to_world ree \$mypid]
set ree \$ree_data(spid)
set ree_port \$ree_data(port)

if { \$QEMU_TEE_SYSTEM_MODE == 0 } {
  set console \$hee
} else {
  set console \$tee
}

set env(FUCHSIA_IP) ${FUCHSIA_IP}
printf "using \$env(FUCHSIA_IP)...\n"

spawn ${cmd}
set timeout 30
set qemu \$spawn_id
expect {
  default {
    printf "TIMEOUT or EOF...\n"
    exit 1
  }
  -i \$qemu "(qemu) "
}
printf "spawned OK (\$qemu)...\n"
send -i \$qemu "c\r"
expect {
  default {
    printf "TIMEOUT or EOF...\n"
    exit 1
  }
  -i \$qemu "(qemu) "
}
printf "cont OK...\n"

EOF
}

# caller should ensure the file path exist.
function expect-load-file {
  local SCRIPT="${1}"
  local PROMPT_CHECK="${2:-false}"
  if [[ "${PROMPT_CHECK}" = "true" ]]; then
    cat >> "${FINAL_EXPECT_SCRIPT}" << EOF
#### Auto-generated prompt check
EOF
    # GRT(TODO): remove the HEE check, but what is used to check ?
    if [ "$USE_RELEASE" != "true" ]; then
      cat "${HEE_PROMPT_CHECK}"  >> "${FINAL_EXPECT_SCRIPT}"
    fi
    cat "${REE_PROMPT_CHECK}"  >> "${FINAL_EXPECT_SCRIPT}"
  fi
  cat >> "${FINAL_EXPECT_SCRIPT}" << EOF
############################################################
#### $(basename ${SCRIPT})
############################################################
printf "Running: $(basename ${SCRIPT})\n"
set exp_running [clock clicks -milliseconds]
EOF
  cat "${SCRIPT}"  >> "${FINAL_EXPECT_SCRIPT}"
  cat >> "${FINAL_EXPECT_SCRIPT}" << EOF
set exp_finished [clock clicks -milliseconds]
printf "Finished: $(basename ${SCRIPT}) ([formatTimeInterval [expr {\$exp_finished - \$exp_running}]])\n"
EOF
}

# create a temporary expect section for input command
function expect-load-cmd {
  IFS=':' read -r -a array <<< "${1}"
  [[ ${#array[@]} -lt 2 ]] && usage && exit 1

  # world1/2,prompt1/2: 1 is primary expect, 2 is for dummy expect, see #422
  local world1=""
  local world2=""
  local command="${array[1]}"
  local timeout="${array[2]:-"-1"}" # default -1, never timeout
  local loopmax="${array[3]:-"1"}"  # default loop once
  local prompt1=""
  local prompt2=""

  local send_opt=""
  local sos_attach=""

  case "${array[0]}" in
    hee) world1="hee"; world2="ree"; prompt1="$ "; prompt2="root@FVP:/ " ;;
    ree) world1="ree"; world2="hee"; prompt1="root@FVP:/ "; prompt2="$ " ;;
    *) usage ; exit 1 ;;
  esac
  # With an active hypervisor the SOS shell is on the HEE console (vmm shell).
  if [[ "${array[0]}" == "ree" ]] && [[ "${QEMU_ACTIVE_HYP}" == "on" ]]; then
    world1="hee"; world2="ree"; prompt2="root@FVP:/ "; send_opt="-s "; sos_attach="true"
  fi

  cat >> "${FINAL_EXPECT_SCRIPT}" << EOF
############################################################
#### WORLD: 1=${world1} 2=${world2}, CMD: ${command}, TIMEOUT=${timeout}
############################################################
set cmd_result_code 0
set loop 0
EOF
  if [[ -n "${sos_attach}" ]]; then
    cat >> "${FINAL_EXPECT_SCRIPT}" << EOF
if {![sos_attach \$hee 60]} {
    printf "SOS console TIMEOUT !!!\n"
    exit 1
}
EOF
  fi
  cat >> "${FINAL_EXPECT_SCRIPT}" << EOF
while {\$loop < ${loopmax}} {
  printf "Running: ${command} (loop=\$loop)\n"
  set exp_running [clock clicks -milliseconds]
  send ${send_opt}-i \$${world1} "${command}; echo cmd_result_code=\$?\r"
  set timeout ${timeout}
  expect {
    timeout {
        printf "Timeout !!!\n"
        exit 1
    }
    -i \$${world1} -re "cmd_result_code=(\[-\]?\[0-9\]+)" {
      set cmd_result_code \$expect_out(1,string)
      if {\$cmd_result_code != 0} {
        printf "${command} FAILED !!!\n"
        exit \$cmd_result_code
      } else {
        exp_continue
      }
    }
    # DummyRead to avoid expect log full from the other world
    -i \$${world2} "${prompt2}" {
        exp_continue
    }
    -i \$${world1} "${prompt1}"
  }
  set exp_finished [clock clicks -milliseconds]
  printf "Finished: ${command} (loop=\$loop) ([formatTimeInterval [expr {\$exp_finished - \$exp_running}]])\n"
  incr loop
}
EOF
  if [[ -n "${sos_attach}" ]]; then
    echo 'sos_detach $hee' >> "${FINAL_EXPECT_SCRIPT}"
  fi
}

# args: "${QEMU_RUN_CHECK}" ${JOB} ${EXPECT_JOBS}
function expect-load-scripts {
  expect-prologue
  if [[ "${1}" = "all" ]]; then
    expect-load-default-check "2" ${2} ${3}
  elif [[ "${1}" = "ut-all" ]]; then
    expect-load-default-check "1" ${2} ${3}
  elif [[ ! -z "${1}" ]]; then
    if [[ -f "${EXPECTS_DIR}/${1}" ]]; then
      expect-load-file "${EXPECTS_DIR}/${1}" true
    else
      expect-load-cmd "${1}"
    fi
  fi
  expect-epilogue
}

function expect-prologue {
  for exp in `find "${EXPECTS_DIR}/boot" -maxdepth 1 -type f | sort`; do
    if [[ $(basename ${exp}) == [HR]EE-BOOT.exp ]]; then
      expect-load-file ${exp} false
    fi
  done
}

function expect-epilogue {
  cat >> "${FINAL_EXPECT_SCRIPT}" << EOF
send -i \$qemu "q\r"
wait -i \$qemu
printf "closed...\n"
close -i \$hee
wait -i \$hee
printf "serial-hee-\$mypid:\$hee_port closed...\n"
close -i \$ree
wait -i \$ree
printf "serial-ree-\$mypid:\$ree_port closed...\n"
close -i \$tee
wait -i \$tee
printf "serial-tee-\$mypid:\$tee_port closed...\n"
EOF
}

function expect-load-default-check {
  local path_depth=${1:-2}
  local job="${2:-0}"
  local jobs=${3:-0}
  local expfiles=($(find "${EXPECTS_DIR}" -maxdepth ${path_depth} -type f | sort))
  local regex='^[A-Z]{3}-[0-9]{4}-.*\.exp'
  for id in $(seq 0 $((${#expfiles[@]}-1))); do
    if [[ $(basename ${expfiles[$id]}) =~ $regex ]]; then
      if [[ ${jobs} -le 1 ]]; then
        expect-load-file ${expfiles[$id]} true
      else
        if [[ $((${id} % ${jobs})) -eq ${job} ]]; then
          expect-load-file ${expfiles[$id]} true
        fi
      fi
    fi
  done
}
