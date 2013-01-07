#!/bin/sh
#
# slackbuilder_funcs.sh - Support functions for package building
#
# Written by Ken Zalewski
# First release on 2012-04-02
# Last revised on 2012-07-25
#


[ "$PROG" ] || PROG=`basename $0`


find_broken_symlinks() {
  # If the broken symlink file is a man page, delete it, recreate it with
  # a .gz extension, and recreate the target with a .gz extension.
  # Otherwise, just report on the broken symlink.
  find -follow -type l 2>&1 | sed -e "s;^find: ;;" -e "s;: No such.*$;;" | \
  while read fname; do
    case "$fname" in
      ./usr/man/*)
        target=`readlink $fname`
        rm -f $fname
        ln -s "$target.gz" "$fname.gz"
        echo "Recreated broken symbolic link $fname as $fname.gz -> $target.gz"
        ;;
      *) echo "$PROG: $fname: Broken symbolic link to $target" >&2
    esac
  done
}


absolute_to_relative() {
  d="$1"
  cd $d

  find -type l -ls | \
  cut -c68- | \
  grep "\-> $d" | \
  sed "s; -> $d;   .;" | \
  while read base_file links_to; do
    f1=$base_file
    f2=$links_to
    keep_going=1

    echo "File $base_file links to absolute path $d$links_to"

    while [ $keep_going -eq 1 ]; do
      # Obtain the prefix from both pathnames.
      f1_prefix=`expr $f1 : "\([^/]*/\)"`
      f2_prefix=`expr $f2 : "\([^/]*/\)"`

      if [ "$f1_prefix" -a "$f1_prefix" = "$f2_prefix" ]; then
        # Trim the common prefix from both pathnames.
        f1=`echo $f1 | sed "s;^[^/]*/;;"`
        f2=`echo $f2 | sed "s;^[^/]*/;;"`
        echo "$f1 $f2"
      else
        keep_going=0
      fi
    done

    # Each slash left in $f1 represents the number of parent directories
    # that must be backtracked for $f2 to get to its destination.
    f2=`echo $f1 | sed -e "s;[^/]*/;../;g" -e "s;[^/]*$;;"`"$f2"

    echo "Re-creating $base_file with link to $f2"
    rm -f $base_file
    ln -s $f2 $base_file
  done
}


# This function is no longer used, but I'm keeping it around anyway.
calc_build_dir() {
  base="$1"
  vers="$2"
  result=
  for trydir in "$base-$vers" "${base}_$vers" "$base.$vers" "$base"; do
    if [ -d "$trydir" ]; then
      result="$trydir"
      break
    fi
  done

  if [ ! "$result" ]; then
    result=`find -maxdepth 1 -type d -iname "$base*"`
  fi

  echo "$result"
}


tolowercase() {
  tr "[:upper:]" "[:lower:]"
}


is_relative_path() {
  p="$1"
  echo $p | cut -c1 | grep -v "/" >/dev/null
}


set_prefix_vars() {
  prefix="$1"
  rprefix=`echo $prefix | sed "s;^/;;"`
}


strip_elfs_in_dirs() {
  echo "Searching for and stripping ELF files"
  find "$@" -type f -print0 | xargs -0 file | egrep "ELF| ar archive" | cut -f1 -d: | xargs strip --strip-unneeded 2>/dev/null
}


is_config_section() {
  local cfgfile="$1"
  local cfgsect="$2"
  grep -q "^\[$cfgsect\] *$" "$cfgfile" 2>/dev/null
  return $?
}


get_config_section() {
  local cfgfile="$1"
  local cfgsect="$2"
  sed -n -e "/^\[$cfgsect\] *\$/,/^\[[^ ]/p" "$cfgfile" | egrep -v '^(\[[^ ]|#)'
}


gen_slack_desc() {
  local cfgfile="$1"
  local summary="$2"
  local pkgrname="$3"
  local pkgrmail="$4"
  local lcaseopt=
  [ "$pkgname" ] || pkgname=`basename $cfgfile | cut -d. -f1`
  [ "$lowercase" ] || lowercase=0
  [ $lowercase -eq 1 ] && lcaseopt="--lowercase"
  get_config_section "$cfgfile" "slack-desc" | \
  genslackdesc.sh $pkgname $lcaseopt -f -n "$pkgrname" -e "$pkgrmail" -s "$summary"
}


exec_cfg_cmds() {
  local cfgfile="$1"
  local cfgsect="$2"
  local tmpdir="$3"

  [ "$tmpdir" ] || tmpdir="$TEMP_DIR"
  [ "$tmpdir" ] || tmpdir="tmp"

  if is_config_section "$cfgfile" "$cfgsect"; then
    echo "$PROG: Processing [$cfgsect] commands from package config file" >&2
    get_config_section "$cfgfile" "$cfgsect" >"$tmpdir/$cfgsect.sh"
    source "$tmpdir/$cfgsect.sh"
#    if get_config_section "$cfgfile" "$cfgsect" | sh -ux; then
    if [ $? -eq 0 ]; then
      echo "$PROG: Completed [$cfgsect] commands" >&2
      return 0
    else
      echo "$PROG: [$cfgsect] commands failed" >&2
      return 1
    fi
  else
    echo "$PROG: No [$cfgsect] commands to process from package config file" >&2
    return 0
  fi
}

exec_var_cmds() {
  local cmds="$1"
  local phase="$2"

  if [ "$cmds" ]; then
    echo "$PROG: Processing [$phase] commands from script variable" >&2
    if sh -x -c "$cmds"; then
      echo "$PROG: Completed [$phase] commands" >&2
      return 0
    else
      echo "$PROG: [$phase] commands failed" >&2
      return 1
    fi
  else
    echo "$PROG: No [$phase] commands to process from script variable" >&2
    return 0
  fi
}


generate_config_installer_func() {
  cat <<"EOF"
install_config_file() {
  cfgfile="$1"
  origcfgfile=`echo $cfgfile | sed "s;\.new\$;;"`
  if [ -f "$origcfgfile" ]; then
    echo "Leaving file $origcfgfile in tact"
    if cmp -s "$origcfgfile" "$cfgfile"; then
      echo "Removing $cfgfile since it is identical to $origcfgfile"
      rm "$cfgfile"
    fi
  else
    mv "$cfgfile" "$origcfgfile"
  fi
}
EOF
}

