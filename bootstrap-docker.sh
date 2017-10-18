#!/usr/bin/env bash

set -exfu
umask 0022

function main {
  local nm_branch="v20170617"
  local nm_remote="gh"
  local url_remote="https://github.com/imma/ubuntu"

  export BOARD_PATH="$HOME"

  : ${DISTRIB_ID:=}

  if [[ -f /etc/lsb-release ]]; then
    . /etc/lsb-release
  fi

  if [[ -z "${DISTRIB_ID}" ]]; then
    DISTRIB_ID="$(awk '{print $1}' /etc/system-release 2>/dev/null || true)"
  fi

  if [[ -z "${DISTRIB_ID}" ]]; then
    DISTRIB_ID="$(awk '{print $1}' /etc/redhat-release 2>/dev/null || true)"
  fi

  if [[ -z "$DISTRIB_ID" ]]; then
    DISTRIB_ID="$(uname -s)"
  fi

  export DISTRIB_ID

  case "$DISTRIB_ID" in
    Ubuntu)
      local loader='sudo env DEBIAN_FRONTEND=noninteractive'
      ;;
    *)
      local loader='sudo env'
      ;;
  esac

  if [[ ! -d .git || -f .bootstrapping ]]; then
    touch .bootstrapping

    case "$DISTRIB_ID" in
      Ubuntu)
        $loader apt-get install -y awscli
        $loader dpkg --configure -a
        $loader apt-get update
        $loader apt-get install -y make python build-essential aptitude git rsync
        $loader aptitude hold grub-legacy-ec2 docker-ce lxd
        $loader apt-get upgrade -y
        ;;
      Amazon)
        $loader yum install -y aws-cli
        $loader yum install -y git rsync make
        ;;
      CentOS)
        $loader yum install -y wget curl rsync make

        wget -nc https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
        (set +f; $loader rpm -Uvh epel-release-latest-7*.rpm || true)

        wget https://centos7.iuscommunity.org/ius-release.rpm
        (set +f; $loader rpm -Uvh ius-release*.rpm || true)

        $loader yum install -y git2u
        ;;
    esac

    ssh -o StrictHostKeyChecking=no git@github.com true 2>/dev/null || true

    tar xfz /data/cache/git/ubuntu-v20170616.tar.gz
    git reset --hard
    rsync -ia .gitconfig.template .gitconfig
    rsync -ia .ssh/config.template .ssh/config
    chmod 600 .ssh/config

    git remote add "${nm_remote}" "${url_remote}" 2>/dev/null || true
    git remote set-url "${nm_remote}" "${url_remote}"
    git fetch "${nm_remote}"
    git branch -D "${nm_remote}/$nm_branch" || true
    git branch --set-upstream-to "${nm_remote}/$nm_branch"
    git reset --hard "${nm_remote}/${nm_branch}"
    git checkout "${nm_branch}" 
    if ! git submodule update --init; then
      set +f
      for a in work/*/; do
        a="${a%/}"
        if [[ ! -L "$a" ]]; then
          if ! git submodule update --init "$a"; then
            rm -rf ".git/modules/$a" "$a"
            git submodule update --init "$a"
          fi
        fi
      done
      set -f
      git submodule foreach 'git reset --hard; git clean -ffd'
    fi
    git submodule update --init

    work/base/script/bootstrap
    work/jq/script/bootstrap
    work/block/script/cibuild

    rm -f .bootstrapping
  fi

  git fetch
  git reset --hard
  git clean -ffd

  source work/block/script/profile ~
  make cache
  source .bash_profile

  block sync
  source .bash_profile
  block bootstrap
  sync
}

case "$(id -u -n)" in
  root)
    umask 022

    cat > /etc/sudoers.d/90-cloud-init-users <<____EOF
    # Created by cloud-init v. 0.7.9 on Fri, 21 Jul 2017 08:42:58 +0000
    # User rules for ubuntu
    ubuntu ALL=(ALL) NOPASSWD:ALL
____EOF

    ssh -A -o BatchMode=yes -o StrictHostKeyChecking=no ubuntu@localhost "$0"
    ;;
  *)
    main "$@"
    ;;
esac
