#!/bin/bash
# Copyright 2019 GoldenRiver Technology Co., Ltd. All rights reserved.
#
# The present software is the confidential and proprietary information of
# GoldenRiver Technology Co., Ltd. You shall not disclose the present
# software and shall use it only in accordance with the terms of the license
# agreement you entered into with GoldenRiver Technology Co., Ltd.
# This software may be subject to export or import laws in certain countries.
#

function gerrit_query() {
  # TODO: for now GRT gerrit does not support mulit-master mode,
  #       we need to query patch from gerrit-review.
  #       If multi-master is implemented, we can use 'gerrit' to
  #       acccess gerrit server directly.
  ssh -n -p 29418 gerrit-review gerrit query --current-patch-set "status:open $1"
}

function gerrit_patch_query() {
  local change_nums="$(gerrit_query "${1}" | grep "^  number:" | awk '{print $2}')"
  local str=""
  local res=""

  # pattern match: project, change Id, change number, patchset number, revision, refspec
  local regex='project: ([0-9a-z.A-Z\/_-]+) .+'
  local regex+='id: ([0-9a-zA-Z]+)  number: ([0-9]+) .+'
  local regex+='currentPatchSet:    number: ([0-9]+)    revision: ([0-9a-zA-Z]+) .+'
  local regex+='ref: ([0-9a-zA-Z\/]+)'

  for num in ${change_nums}; do
    str="$(gerrit_query "change:${num}" | tr -d '\n')"
    if [[ "${str}" =~ $regex ]]; then
      res+="project:${BASH_REMATCH[1]},"
      res+="change_id:${BASH_REMATCH[2]},"
      res+="change_num:${BASH_REMATCH[3]},"
      res+="patchset_num:${BASH_REMATCH[4]},"
      res+="revision:${BASH_REMATCH[5]},"
      res+="ref:${BASH_REMATCH[6]}&"
    else
      >&2 echo "Failed to match pattern"
      exit 1
    fi
  done

  echo $res
}

function get_project() {
  local regex='project:([0-9a-z.A-Z\/_-]+)'
  if [[ "${1}" =~ $regex ]];then
    echo ${BASH_REMATCH[1]}
  fi
}

function get_change_id() {
  local regex='change_id:([0-9a-zA-Z]+)'
  if [[ "${1}" =~ $regex ]];then
    echo ${BASH_REMATCH[1]}
  fi
}

function get_change_num() {
  local regex='change_num:([0-9]+)'
  if [[ "${1}" =~ $regex ]];then
    echo ${BASH_REMATCH[1]}
  fi
}

function get_patchset_num() {
  local regex='patchset_num:([0-9]+)'
  if [[ "${1}" =~ $regex ]];then
    echo ${BASH_REMATCH[1]}
  fi
}

function get_revision() {
  local regex='revision:([0-9a-zA-Z]+)'
  if [[ "${1}" =~ $regex ]];then
    echo ${BASH_REMATCH[1]}
  fi
}

function get_ref() {
  local regex='ref:([0-9a-zA-Z\/]+)'
  if [[ "${1}" =~ $regex ]];then
    echo ${BASH_REMATCH[1]}
  fi
}
