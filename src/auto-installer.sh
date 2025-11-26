#!/bin/bash
##############################################
##                                          ##
##  auto-installer                          ##
##                                          ##
##############################################

SCRIPT_TITLE="auto-installer"
SCRIPT_VERSION="1.1"
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
SYS_ARCH=$(dpkg --print-architecture)
PREREQS=( dpkg sed jq curl )
export LC_ALL=C
export LANG=C

for i in "$@"
do
  case $i in
    -V|--verbose)
    verbose="--verbose"
    shift # past argument
    ;;
    -q|--quiet)
    quiet="--quiet"
    shift # past argument
    ;;
    -f|--force)
    force="--force"
    shift # past argument
    ;;
    -i|--install)
    [ -z "$CMD" ] && CMD="install" || CMD="help"
    shift # past argument
    ;;
    -d|--deinstall)
    [ -z "$CMD" ] && CMD="deinstall" || CMD="help"
    shift # past argument
    ;;
    -v|--version)
    [ -z "$CMD" ] && CMD="version" || CMD="help"
    shift # past argument
    ;;
    -h|--help)
    CMD="help"
    shift # past argument
    ;;
    *)
    if [ "$i" != "" ]
    then
      echo "Unknown option: $i"
      exit 1
    fi
    ;;
  esac
done
[ -z "$CMD" ] && CMD="help"

handle_error() {
  local exit_code=$1
  local error_message="$2"
  if [ -z "$exit_code" ] || [ "$exit_code" == "0" ]; then
    exit_code=1
  fi
  echo -e "error: $error_message (Exit Code: $exit_code)"
  exit $exit_code
}

do_check_start() {
  if [ $UID -ne 0 ]; then
    handle_error "1" "This script can only run with Superuser privileges!"
  fi
  if ! [ -f "/etc/debian_version" ]; then
    handle_error "1" "This script is only supported on Debian-based systems."
  fi
  local apt
  local apt_res=""
  IFS=$' '
  if [ "${#PREREQS[@]}" -ne 0 ]; then
    for apt in "${PREREQS[@]}"; do
      if ! { dpkg -s "$apt" 2>/dev/null | grep -q '^Status: install ok installed'; }; then
        apt_res+="${apt} "
      fi
    done
    if [ -n "$apt_res" ]; then
      [ -z "$quiet" ] && echo "--> run apt-get update ..."
      if [ -z "$verbose" ]; then
        apt-get -qy update >/dev/null 2>&1
      else
        apt-get -qy update
      fi
      [ $? -ne 0 ] && handle_error "1" "apt-get update error! abort."
      [ -z "$quiet" ] && echo "--> install missing prerequisites: ${apt_res% } ..."
      if [ -z "$verbose" ]; then
        apt-get install -qq -- ${apt_res% } >/dev/null 2>&1
      else
        apt-get install -qq -- ${apt_res% }
      fi
      [ $? -ne 0 ] && handle_error "1" "Could not install prerequisites: ${apt_res% }! abort."
    fi
  fi
  unset IFS
}

scripts_setup() {
  local filetype
  local entry
  local test
  local old_IFS="$IFS"
  IFS=$'\n'
  test=($(find "$SCRIPT_DIR" -maxdepth 1 -type f -name "*$1.sh" 2>/dev/null))
  if [ "${#test[@]}" != "0" ]; then
    for entry in "${test[@]}"; do
      [[ "$entry" -ef "$SCRIPT_PATH" ]] && continue
      filetype=$(file -b --mime-type "$entry" 2>/dev/null)
      if [[ "$filetype" =~ "text" ]]
      then
        sed -i 's/\r$//g' "$entry" >/dev/null 2>&1
        filetype="$(file -b --mime-type "$entry" 2>/dev/null)"
      fi
      if [[ "$filetype" =~ "executable" ]] || [[ "$filetype" =~ "script" ]] || [[ "$entry" == *".sh" ]]; then
        chmod -f 755 "$entry"
        "$entry" $quiet $force $verbose
      fi
    done
  fi
  IFS="$old_IFS"
}

gh_deb_download() {
  local repo="$1"
  local token="$2"
  local api_base="https://api.github.com"
  local release_json
  local etag_dir="$SCRIPT_DIR/.etag"
  mkdir -p "$etag_dir"
  local base="$(echo -n "$repo" | tr '/' '_')"
  local etag_file="$etag_dir/$base.etag"
  local cache_json="$etag_dir/$base.json"
  local hdr="$(mktemp)"
  local body="$(mktemp)"
  local etag_header=()
  [[ -f "$etag_file" ]] && etag_header=(-H "If-None-Match: $(cat "$etag_file")")
  local code
  [ -z "$quiet" ] && echo "--> get github-releases info: $repo ..."
  code=$(curl -fs ${verbose:+-vS} \
      -D "$hdr" \
      -w "%{http_code}" \
      -o "$body" \
      -H "User-Agent: $SCRIPT_TITLE/$SCRIPT_VERSION" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      ${token:+-H} ${token:+"Authorization: Bearer $token"} \
      "${etag_header[@]}" \
      "$api_base/repos/$repo/releases/latest")
  if [[ "$code" == "304" ]]; then
    rm -f "$hdr" "$body"
    if [[ -f "$cache_json" ]]; then
      release_json="$(cat "$cache_json")"
    else
      release_json="$(curl -fsL ${verbose:+-vS} \
        -H "User-Agent: $SCRIPT_TITLE/$SCRIPT_VERSION" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        ${token:+-H} ${token:+"Authorization: Bearer $token"} \
        "$api_base/repos/$repo/releases/latest")" || handle_error "1" "Could not receive release for repo $repo"
      echo "$release_json" > "$cache_json"
    fi
  else
    if [[ "$code" != "200" ]]; then
      rm -f "$hdr" "$body"
      handle_error "1" "Could not receive release for repo $repo (HTTP $code)"
    fi
    if grep -qi '^etag:' "$hdr"; then
      sed -n 's/^[eE][tT][aA][gG]: *//p' "$hdr" | tr -d '\r' > "$etag_file"
    fi
    release_json="$(cat "$body")"
    echo "$release_json" > "$cache_json"
    rm -f "$hdr" "$body"
  fi
  mapfile -t asset_lines < <(
    printf "%s\n" "$release_json" |
    jq -r '.assets[]? | select(.name|endswith(".deb")) | "\(.id)\t\(.name)\t\(.browser_download_url // "")\t\(.size // 0)"'
  )
  [[ ${#asset_lines[@]} -eq 0 ]] && handle_error "1" "Could not find any .deb-assets in repo $repo"
  for line in "${asset_lines[@]}"; do
    local id="${line%%$'\t'*}"
    local rest="${line#*$'\t'}"
    local name="${rest%%$'\t'*}"
    rest="${rest#*$'\t'}"
    local url="${rest%%$'\t'*}"
    local size="${rest#*$'\t'}"
    local dest="$SCRIPT_DIR/$name"
    if [[ -f "$dest" ]] && [[ -z "$force" ]]; then
      local cur_size
      cur_size=$(stat -c%s "$dest" 2>/dev/null || echo 0)
      if [[ "$size" -gt 0 && "$cur_size" -eq "$size" ]]; then
        [ -z "$quiet" ] && echo "Skipping download (up-to-date): $name"
        continue
      fi
    fi
    [ -z "$quiet" ] && echo "--> Download: $repo → $name"
    if [[ -n "$url" ]] && curl -fsL ${verbose:+-vS} \
       -H "User-Agent: $SCRIPT_TITLE/$SCRIPT_VERSION" \
       "$url" -o "$dest"; then
      continue
    fi
    curl -fsL ${verbose:+-vS} \
      -H "User-Agent: $SCRIPT_TITLE/$SCRIPT_VERSION" \
      -H "Accept: application/octet-stream" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      ${token:+-H} ${token:+"Authorization: Bearer $token"} \
      "$api_base/repos/$repo/releases/assets/$id" \
      -o "$dest" || handle_error "1" "Download error: $name"
  done
}

github_download() {
  local repo
  local token
  local conf_file="$SCRIPT_DIR/github.conf"
  [[ ! -f "$conf_file" ]] && return 0
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs)"
    [[ -z "$line" ]] && continue
    repo=$(awk '{print $1}' <<< "$line")
    token=$(awk '{print $2}' <<< "$line")
    [[ -z "$repo" ]] && continue
    gh_deb_download "$repo" "$token"
  done < "$conf_file"
}

deb_setup() {
  local filetype
  local deb_file
  local deb_pkg
  local deb_arch
  local deb_ver
  local inst_ver
  local entry
  local test
  local old_IFS="$IFS"
  IFS=$'\n'
  test=($(find "$SCRIPT_DIR" -maxdepth 1 -type f -name "*.deb" 2>/dev/null))
  if [ "${#test[@]}" != "0" ]; then
    if [ "$1" == "" ]; then
      [ -z "$quiet" ] && echo "--> run apt-get update ..."
      if [ -z "$verbose" ]; then
        apt-get -qy update >/dev/null 2>&1
      else
        apt-get -qy update
      fi
      [ $? -ne 0 ] && handle_error "1" "apt-get update error! abort."
    fi
    for entry in "${test[@]}"; do
      filetype=$(file -b --mime-type "$entry" 2>/dev/null)
      if [[ "$filetype" =~ "package" ]] || [[ "${entry##*.}" == "deb" ]]; then
        deb_file=$(basename "$entry")
        deb_pkg=$(dpkg-deb -f "$entry" Package 2>/dev/null)
        deb_arch=$(dpkg-deb -f "$entry" Architecture 2>/dev/null)
        deb_ver=$(dpkg-deb -f "$entry" Version 2>/dev/null)
        inst_ver=$(dpkg -s -- "$deb_pkg" 2>/dev/null | awk '/^Version:/{print $2}')
        if [[ -z "$deb_pkg" ]] || [[ -z "$deb_arch" ]] || [[ -z "$deb_ver" ]]; then
          handle_error "1" "Package error: $deb_file (missing Package/Architecture/Version) ! abort."
        elif [ "$deb_arch" = "$SYS_ARCH" ] || [ "$deb_arch" = "all" ]; then
          if [[ -n "$force" ]] && [[ -z "$1" ]]; then
            [ -z "$quiet" ] && echo "--> force install: $deb_file ..."
            if [ -z "$verbose" ]; then
              apt-get install -qq --reinstall --allow-downgrades -- "$entry" >/dev/null 2>&1
            else
              apt-get install -qq --reinstall --allow-downgrades -- "$entry"
            fi
            [ $? -ne 0 ] && handle_error "1" "install error: $deb_file ! abort."
          elif [[ -n "$force" ]] && [ "$1" == "-d" ]; then
            [ -z "$quiet" ] && echo "--> force deinstall: $deb_file ..."
            if [ -z "$verbose" ]; then
              apt-get remove -qq -- "$deb_pkg" >/dev/null 2>&1
            else
              apt-get remove -qq -- "$deb_pkg"
            fi
            [ $? -ne 0 ] && handle_error "1" "deinstall error: $deb_file ! abort."
          elif [[ -n "$inst_ver" ]] && dpkg --compare-versions "$deb_ver" eq "$inst_ver" && [[ -z "$1" ]]; then
            [ -z "$quiet" ] && echo "Skipping installation (up-to-date): $deb_file"
          elif ( [[ -z "$inst_ver" ]] || dpkg --compare-versions "$deb_ver" gt "$inst_ver" ) && [[ -z "$1" ]]; then
            [ -z "$quiet" ] && echo "--> install: $deb_file ..."
            if [ -z "$verbose" ]; then
              apt-get install -qq -- "$entry" >/dev/null 2>&1
            else
              apt-get install -qq -- "$entry"
            fi
            [ $? -ne 0 ] && handle_error "1" "install error: $deb_file ! abort."
          elif [[ -z "$inst_ver" ]] && [ "$1" == "-d" ]; then
            [ -z "$quiet" ] && echo "Skipping (not installed): $deb_file"
          elif [[ -n "$inst_ver" ]] && [ "$1" == "-d" ]; then
            [ -z "$quiet" ] && echo "--> deinstall: $deb_file ..."
            if [ -z "$verbose" ]; then
              apt-get remove -qq -- "$deb_pkg" >/dev/null 2>&1
            else
              apt-get remove -qq -- "$deb_pkg"
            fi
            [ $? -ne 0 ] && handle_error "1" "deinstall error: $deb_file ! abort."
          fi
        else
          [ -z "$quiet" ] && echo "Skipping $deb_file (arch: $deb_arch, needed: $SYS_ARCH)"
        fi
      fi
    done
  fi
  IFS="$old_IFS"
}

function cmd_install() {
  scripts_setup preinst
  github_download
  deb_setup
  scripts_setup postinst
}

function cmd_deinstall() {
  scripts_setup prerm
  github_download
  deb_setup -d
  scripts_setup postrm
}

function cmd_print_version() {
  echo "$SCRIPT_TITLE v$SCRIPT_VERSION"
}

function cmd_print_help() {
  echo "Usage: $SCRIPT_NAME [OPTION]"
  echo "$SCRIPT_TITLE v$SCRIPT_VERSION"
  echo " "
  echo "A lightweight shell script to automatically run installer"
  echo "scripts and install or deinstall '.deb' packages from"
  echo "the script directory and/or GitHub Releases."
  echo "The script looks for files in the same directory, then:"
  echo "- run '*preinst.sh'/'*prerm.sh' scripts"
  echo "- download '.deb' files from GitHub Releases (from 'github.conf')"
  echo "- de-/install '.deb' files found in the script directory"
  echo "- run '*postinst.sh'/'*postrm.sh' scripts"
  echo " "
  echo "-i, --install           run scripts and install all packages"
  echo "-d, --deinstall         run scripts and deinstall all packages"
  echo "-f, --force             force deinstall or reinstall packages"
  echo "-q, --quiet             do not print informations while de-/installation"
  echo "-V, --verbose           print detailed information during de-/installation"
  echo "-v, --version           print version info and exit"
  echo "-h, --help              print this help and exit"
  echo " "
  echo "Author: aragon25 <aragon25.01@web.de>"
}

[ "$CMD" != "version" ] && [ "$CMD" != "help" ] &&  do_check_start
[[ "$CMD" == "version" ]] && cmd_print_version
[[ "$CMD" == "help" ]] && cmd_print_help
[[ "$CMD" == "install" ]] && cmd_install
[[ "$CMD" == "deinstall" ]] && cmd_deinstall

exit 0