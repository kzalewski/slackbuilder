#!/bin/sh
#
# slackbuilder.sh - Build Slackware packages
#
# Written by Ken Zalewski
# First release on 2012-04-02
# Last revised on 2012-07-25
#

PROG=`basename $0`
PROGNAME=`basename $0 .sh`
SYSTEM_CFGFILE=/etc/$PROGNAME.cfg
USER_CFGFILE=$HOME/.$PROGNAME.cfg
CURDIR=$PWD

DEFAULT_PKGR_NAME="Slackware Packager"
DEFAULT_PKGR_EMAIL="packager@slackware.com"
DEFAULT_PKGR_INITS=pkg
DEFAULT_PKG_EXT=txz
DEFAULT_PREFIX=/usr
DEFAULT_KDEPREFIX=/opt/kde
DEFAULT_X11PREFIX=/usr/X11R6
DEFAULT_CFLAGS_i386="-O2 -march=i386 -mtune=i686"
DEFAULT_CFLAGS_i486="-O2 -march=i486 -mtune=i686"
DEFAULT_CFLAGS_i586="-O2 -march=i586 -mtune=i686"
DEFAULT_CFLAGS_i686="-O2 -march=i686 -mtune=i686"
DEFAULT_CFLAGS_s390="-O2"
DEFAULT_CFLAGS_x86_64="-O2 -fPIC"
DEFAULT_CFLAGS_arm="-O2 -march=armv4 -mtune=xscale"
DEFAULT_LIBDIRSUFFIX_x86_64="64"
DEFAULT_COMPILEDIR="compile"
DEFAULT_LAYOUTDIR="layout"
DEFAULT_TEMPDIR="temp"
DEFAULT_ARCHIVEDIR="/usr/local/slackware"

[ -r "$SYSTEM_CFGFILE" ] && . "$SYSTEM_CFGFILE"
[ -r "$USER_CFGFILE" ] && . "$USER_CFGFILE"

: ${PKGR_NAME:=$DEFAULT_PKGR_NAME}
: ${PKGR_EMAIL:=$DEFAULT_PKGR_EMAIL}
: ${PKGR_INITS:=$DEFAULT_PKGR_INITS}
: ${PKG_EXT:=$DEFAULT_PKG_EXT}
: ${KDEPREFIX:=$DEFAULT_KDEPREFIX}
: ${X11PREFIX:=$DEFAULT_X11PREFIX}
: ${COMPILEDIR:=$DEFAULT_COMPILEDIR}
: ${LAYOUTDIR:=$DEFAULT_LAYOUTDIR}
: ${TEMPDIR:=$DEFAULT_TEMPDIR}
: ${ARCHIVEDIR:=$DEFAULT_ARCHIVEDIR}

BSUFFIX="-PACKAGE"
DOINST="install/doinst.sh"

: ${ARCH:=`arch`}
cflags_varname=DEFAULT_CFLAGS_$ARCH
libdirsuffix_varname=DEFAULT_LIBDIRSUFFIX_$ARCH
: ${ARCH_CFLAGS:=${!cflags_varname}}
: ${LIBDIRSUFFIX:=${!libdirsuffix_varname}}


usage() {
  echo "Usage: $PROG [-a pkgarch] [-c] [-d build_dir] [-e] [-f archive_file] [-i] [-k] [-n nval] [-o buildopt] [-p pname/pemail/pinits] [-r num] [-s slackver] [-v] [-x] [--arch-cflags gcc-opts] [--notar] [--nocfg] [--nomk] [--noinst] [--noprep] [--nopkg] [--uo] [--cb] [--ucb] [--ip] [--pp] [--po] [--desc] [--gg config_group] packagename version" >&2
  echo "   -a pkgarch: package architecture, such as i486, i686, x86_64, noarch" >&2
  echo "   -c: chown bin directories to root:bin (not necessary since Slackware 11)" >&2
  echo "   -d build_dir: use build_dir as the base for building the package (default: $CURDIR/<pkgname>$BSUFFIX" >&2
  echo "   -e: do not strip ELF files (execs and libs)" >&2
  echo "   -f archive_file: use archive_file as the package source file" >&2
  echo "   -i: force final package filename and docdir to be lowercase" >&2
  echo "   -k: generate a KDE package" >&2
  echo "   -n nval: 'nice' value (0-19) for the make stage" >&2
  echo "   -o buildopt: specify a build option" >&2
  echo "   -p full_name/email/initials: packager name, e-mail, and initials" >&2
  echo "   -r num: run number, for packages that are built using multiple passes" >&2
  echo "   -s slackver: specify the Slackware version" >&2
  echo "   -v: verbose output" >&2
  echo "   -x: generate an X11 package" >&2
  echo "   --arch-cflags gcc-opts: override ARCH_CFLAGS for compilation" >&2
  echo "   --notar: skip the un-tar stage" >&2
  echo "   --nocfg: skip the configure stage" >&2
  echo "   --nomk: skip the 'make' stage" >&2
  echo "   --noinst: skip the 'make install' stage" >&2
  echo "   --noprep: skip the prepare stage" >&2
  echo "   --nopkg: skip the final makepkg stage" >&2
  echo "   --uo: untar only (same as --nocfg --nomk --noinst --noprep --nopkg)" >&2
  echo "   --cb: configure and build (same as --notar --noinst --noprep --nopkg)" >&2
  echo "   --ucb: untar, configure, and build (same as --noinst --noprep --nopkg)" >&2
  echo "   --ip: install and package (same as --notar --nocfg --nomk)" >&2
  echo "   --pp: prepare and package (same as --notar --nocfg --nomk --noinst)" >&2
  echo "   --po: package only (same as --notar --nocfg --nomk --noinst --noprep)" >&2
  echo "   --desc: Display the generated slack-desc file" >&2
  echo "   --gg config_group: get all config data in the specified config group" >&2
}

if [ $# -lt 2 ]; then
  usage
  exit 1
fi

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
  sed -n -e "/^\[$cfgsect\] *\$/,/^\[[^ ]/p" "$cfgfile" | egrep -v '^(\[|#)'
}

gen_slack_desc() {
  local cfgfile="$1"
  local summary="$2"
  local lcaseopt=
  [ $lowercase -eq 1 ] && lcaseopt="--lowercase"
  get_config_section "$cfgfile" "slack-desc" | \
  genslackdesc.sh $pkgname $lcaseopt -f -n "$PKGR_NAME" -e "$PKGR_EMAIL" -s "$summary"
}

exec_cfg_cmds() {
  local cfgfile="$1"
  local cfgsect="$2"
  if is_config_section "$cfgfile" "$cfgsect"; then
    echo "$PROG: Processing [$cfgsect] commands from package config file" >&2
    get_config_section "$cfgfile" "$cfgsect" >"$tempdir/$cfgsect.sh"
    source "$tempdir/$cfgsect.sh"
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


# Variables that can be set from the command line
pkgname=
pkgversion=
pkgarch="$ARCH"
pkgprefix="$DEFAULT_PREFIX"
chgrp_bin=0
build_dir=
strip_elfs=1
archive_file=
lowercase=0
NICE_CMD=
build_opt=standard
packager_info=
run_num=1
slackver=`slackver.sh`

skip_untar_stage=0
skip_config_stage=0
skip_make_stage=0
skip_install_stage=0
skip_prepare_stage=0
skip_pkg_stage=0
slackdesc_only=0
get_config_group=

while [ $# -gt 0 ]; do
  case "$1" in
    -a) shift; pkgarch="$1" ;;
    -c) chgrp_bin=1 ;;
    -d) shift; build_dir="$1" ;;
    -e) strip_elfs=0 ;;
    -f) shift; archive_file="$1" ;;
    -i) lowercase=1 ;;
    -k) pkgprefix="$KDEPREFIX" ;;
    -n) shift; NICE_CMD="nice -n $1" ;;
    -o) shift; build_opt="$1" ;;
    -p) shift; packager_info="$1" ;;
    -r) shift; run_num="$1" ;;
    -s) slackver="$1" ;;
    -v) set -x ;;
    -x) pkgprefix="$X11PREFIX" ;;
    --arch-cflags) shift; ARCH_CFLAGS="$1" ;;
    --uo) skip_untar_stage=0; skip_config_stage=1; skip_make_stage=1;
          skip_install_stage=1; skip_prepare_stage=1; skip_pkg_stage=1 ;;
    --cb) skip_untar_stage=1; skip_config_stage=0; skip_make_stage=0;
          skip_install_stage=1; skip_prepare_stage=1; skip_pkg_stage=1 ;;
    --ucb) skip_untar_stage=0; skip_config_stage=0; skip_make_stage=0;
          skip_install_stage=1; skip_prepare_stage=1; skip_pkg_stage=1 ;;
    --ip) skip_untar_stage=1; skip_config_stage=1; skip_make_stage=1;
          skip_install_stage=0; skip_prepare_stage=0; skip_pkg_stage=0 ;;
    --pp) skip_untar_stage=1; skip_config_stage=1; skip_make_stage=1;
          skip_install_stage=1; skip_prepare_stage=0; skip_pkg_stage=0 ;;
    --po) skip_untar_stage=1; skip_config_stage=1; skip_make_stage=1;
          skip_install_stage=1; skip_prepare_stage=1; skip_pkg_stage=0 ;;
    --desc) slackdesc_only=1 ;;
    --gg) shift; get_config_group="$1" ;;
    --notar) skip_untar_stage=1 ;;
    --nocfg) skip_config_stage=1 ;;
    --nomk) skip_make_stage=1 ;;
    --noinst) skip_install_stage=1 ;;
    --noprep) skip_prepare_stage=1 ;;
    --nopkg) skip_pkg_stage=1 ;;
    -*) echo "$PROG: $1: Unknown option" ; usage; exit 1 ;;
    *) [ "$pkgname" ] && pkgversion="$1" || pkgname="$1" ;;
  esac
  shift
done

if [ ! "$pkgname" ]; then
  echo "$PROG: Must supply the package name" >&2
  exit 1
elif [ ! "$pkgversion" ]; then
  echo "$PROG: Must supply the package version" >&2
  exit 1
fi

if [ "$packager_info" ]; then
  PKGR_NAME=`echo $packager_info | cut -d/ -f1`
  PKGR_EMAIL=`echo $packager_info | cut -d/ -f2`
  PKGR_INITS=`echo $packager_info | cut -d/ -f3`
fi


# Formulate some other variables based on information so far.

set_prefix_vars "$pkgprefix"
pkgbase="$pkgname-$pkgversion"
pkgmajversion=`expr "$pkgversion" : "\([0-9][0-9]*\)"`
pkg_archive="$ARCHIVEDIR/$slackver"
docdir=usr/doc/$pkgbase

[ "$build_dir" ] || build_dir="$CURDIR/$pkgname$BSUFFIX"

if is_relative_path $build_dir; then
  build_dir="$CURDIR/$build_dir"
fi

if [ "$archive_file" ]; then
  if [ ! -r "$archive_file" ]; then
    echo "$PROG: $archive_file: Source archive file not found" >&2
    exit 1
  fi
else
  # Escape any pluses in pkgbase for the egrep pattern.
  pkgbase_pt=`echo $pkgbase | sed 's;+;[+];g'`
  archive_file=`ls -1 | egrep "^$pkgbase_pt([_\.][A-Za-z0-9]+)?\.(tar\.(gz|bz2|lzma|xz)|(tgz|tbz2|tbz|tlz|txz|zip))"`

  if [ $? -ne 0 -a $skip_untar_stage -eq 0 ]; then
    echo "$PROG: Unable to find package $pkgname at version $pkgversion" >&2
    exit 1
  fi
fi

[ $lowercase -eq 1 ] && docdir=`echo $docdir | tolowercase`

# Work directories for package compilation and staging
compiledir="$build_dir/$COMPILEDIR"
destdir="$build_dir/$LAYOUTDIR"
tempdir="$build_dir/$TEMPDIR"
mkdir -p "$compiledir" "$destdir" "$tempdir" || exit 1

# Package-based variables
untar_export_var=
extra_config_env=
extra_config_opts=
extra_doc_files=
extra_doc_dirs=
extra_new_dirs=
specific_strip_dirs=
run_make_depend=0
make_opts=
config_subdir=
compile_subdir=
doc_subdir=
pre_config_cmds=
post_config_cmds=
make_env_vars=
pre_make_cmds=
extra_make_dirs=
post_make_cmds=
destdir_var=
install_env_vars=
pre_install_cmds=
extra_install_opts=
extra_install_dirs=
post_install_cmds=
ignore_install_error=0
setup_script=
post_prepare_cmds=
pre_package_cmds=
post_package_cmds=
python_package=0
ruby_package=0
use_cmake=0
install_docs=1
fix_man_location=1
CONFIG_CMD="./configure"
CONFIG_STD_ENV='CFLAGS="$ARCH_CFLAGS" CXXFLAGS="$ARCH_CFLAGS"'
CONFIG_PREFIX_OPT='--prefix='
CONFIG_STD_OPTS='--build=$ARCH-slackware-linux --libdir=$prefix/lib${LIBDIRSUFFIX} --libexecdir=$prefix/libexec --sysconfdir=/etc --localstatedir=/var --infodir=$prefix/info --mandir=$prefix/man'
MAKE_CMD="make"
INSTALL_CMD="make install"
PKG_CMD="makepkg"
PKG_STD_OPTS="-p -l y -c n"

# All variables listed here will be available to the script commands
# listed in the slack-config file, including the [settings] section, and
# all of the [pre-XXX] and [post-XXX] sections.
export pkgname pkgversion pkgbase
export CURDIR LIBDIRSUFFIX docdir destdir

# Locate the package configuration file for the named package.
# First look for a version-specific config file, then a generic one.
pkgconfig=
if [ -r $pkgbase.slack-config ]; then
  pkgconfig="$pkgbase.slack-config"
elif [ -r $pkgname.slack-config ]; then
  pkgconfig="$pkgname.slack-config"
else
  echo "$PROG: WARNING: No slack-config file was found for package [$pkgname].  Your package build will be very generic and will possibly fail." >&2
fi

if [ "$pkgconfig" ]; then
  pkgconfig="$CURDIR/$pkgconfig"
  # Inject all [settings] variables into the current environment.
  #eval $(get_config_section "$pkgconfig" "settings")
  exec_cfg_cmds "$pkgconfig" "settings" || exit 1

  if [ $slackdesc_only -eq 1 ]; then
    gen_slack_desc "$pkgconfig" "$pkgsummary"
    exit 0
  elif [ "$get_config_group" ]; then
    if is_config_section "$pkgconfig" "$get_config_group"; then
      get_config_section "$pkgconfig" "$get_config_group"
      exit 0
    else
      echo "$PROG: Config section [$get_config_group] is not present" >&2
      exit 1
    fi
  fi
fi

# Standard settings for Python-based packages

if [ $python_package -eq 1 ]; then
  skip_config_stage=1
  MAKE_CMD="python setup.py build"
  INSTALL_CMD="python setup.py install"
  destdir_var="--prefix"
elif [ $use_cmake -eq 1 ]; then
  CONFIG_CMD="cmake"
  CONFIG_PREFIX_OPT="-DCMAKE_INSTALL_PREFIX="
  CONFIG_STD_OPTS="-DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=gcc -DCMAKE_C_FLAGS:STRING=\"$ARCH_CFLAGS\" -DCMAKE_CXX_COMPILER=g++ -DCMAKE_CXX_FLAGS:STRING=\"$ARCH_CFLAGS\" -DCMAKE_MAKE_PROGRAM=gmake -DMAN_INSTALL_DIR=/usr/man"
  destdir_var=DESTDIR
fi



#########################################
# STAGE 1: Un-archive
#########################################

if [ $skip_untar_stage -eq 0 ]; then

  echo "STAGE 1: Un-archive the source code"

  archive_type=`file -b $archive_file | cut -d" " -f1`
  case $archive_type in
    bzip2) UNARCHIVE_CMD="tar -C $compiledir -jxvf" ;;
    gzip) UNARCHIVE_CMD="tar -C $compiledir -zxvf" ;;
    Zip) UNARCHIVE_CMD="unzip -d $compiledir" ;;
    *) echo "$PROG: $archive_file: Unknown file type" >&2 ; exit 1 ;;
  esac

  $UNARCHIVE_CMD $archive_file || { echo "Error: Unable to unarchive the file $archive_file"; exit 1; }
fi

# END OF STAGE 1


# No matter what stages are being skipped, we must determine the
# archive directory.

untardir=`find $compiledir -mindepth 1 -maxdepth 1 -type d`
if [ ! "$untardir" -o `echo "$untardir" | wc -l` -ne 1 ]; then
  echo "$PROG: Unable to determine package untar directory" >&2
  exit 1
else
  echo "Package untar directory: $untardir"
fi

# Some applications require the untar directory to be specified in a variable
# that is exported (for example, Xerces requires the XERCESCROOT variable).
if [ "$untar_export_var" != "" ]; then
  export $untar_export_var="$untardir"
fi


#########################################
# STAGE 2: Configure
#########################################

if [ $skip_config_stage -eq 0 ]; then

  echo "STAGE 2: Configure the package for compilation"

  pushd $untardir || exit 1

  [ "$config_subdir" ] && cd $config_subdir

  exec_cfg_cmds "$pkgconfig" "pre-config" || exit 1
  exec_var_cmds "$pre_config_cmds" "Pre-config" || exit 1

  config_opts=$(get_config_section "$pkgconfig" "config-opts")
  eval $CONFIG_STD_ENV $extra_config_env $CONFIG_CMD $CONFIG_PREFIX_OPT$prefix $CONFIG_STD_OPTS $config_opts $extra_config_opts
  if [ $? -ne 0 ]; then
    echo "$PROG: configure failed" >&2
    exit 1
  fi

  popd

fi

# END OF STAGE 2


#########################################
# STAGE 3: make (including 'make depend')
#########################################

if [ $skip_make_stage -eq 0 ]; then

  echo "STAGE 3: Build the application"

  pushd $untardir || exit 1

  [ "$compile_subdir" ] && cd $compile_subdir

  if [ $run_make_depend -eq 1 ]; then
    $MAKE_CMD depend
    if [ $? -ne 0 ]; then
      echo "$PROG: make depend failed" >&2
      exit 1
    fi
  fi

  exec_cfg_cmds "$pkgconfig" "pre-make" || exit 1
  exec_var_cmds "$pre_make_cmds" "Pre-make" || exit 1

  for d in . $extra_make_dirs; do
    pushd $d
    eval $make_env_vars $NICE_CMD $MAKE_CMD $make_opts
    if [ $? -ne 0 ]; then
      echo "$PROG: Make command '$MAKE_CMD' failed in directory $PWD" >&2
      exit 1
    fi
    popd
  done

  exec_cfg_cmds "$pkgconfig" "post-make" || exit 1
  exec_var_cmds "$post_make_cmds" "Post-make" || exit 1

  popd

fi

# END OF STAGE 3


#########################################
# STAGE 4: install into $destdir
#########################################

if [ $skip_install_stage -eq 0 ]; then

  echo "STAGE 4: Install the application and create the package layout"

  pushd $untardir || exit 1

  [ "$compile_subdir" ] && pushd $compile_subdir

  # We do this again here, even though we did it earlier, because
  # the lowercase option can be set by individual package-specific commands.
  [ $lowercase -eq 1 ] && docdir=`echo $docdir | tolowercase`

  [ $run_num -eq 1 ] && rm -rf $destdir
  mkdir -p $destdir$prefix
  [ $install_docs -eq 1 ] && mkdir -p $destdir/$docdir
  mkdir -p $destdir/install

  exec_cfg_cmds "$pkgconfig" "pre-install" || exit 1
  exec_var_cmds "$pre_install_cmds" "Pre-install" || exit 1

  case "$destdir_var" in
    "")
      echo "$PROG: $pkgname: destdir_var not set for this package" >&2
      exit 1
      ;;
    prefix|--prefix|PREFIX)
      if [ $ruby_package -eq 1 ]; then
        install_destdir=$destdir
      else
        install_destdir=$destdir$prefix
      fi
      ;;
    *)
      install_destdir=$destdir
  esac

  for d in . $extra_install_dirs; do
    pushd $d
    eval $install_env_vars $INSTALL_CMD $destdir_var=$install_destdir $extra_install_opts

    if [ $? -ne 0 ]; then
      echo "$PROG: Installation command '$INSTALL_CMD' failed in directory $PWD" >&2
      if [ $ignore_install_error -eq 1 ]; then
        echo "$PROG: Ignoring installation error and continuing" >&2
      else
        exit 1
      fi
    fi
    popd
  done

  [ "$compile_subdir" ] && popd

  if [ $install_docs -eq 1 ]; then
    [ "$doc_subdir" ] && pushd $doc_subdir
    eval cp -v ABOUT* ANNOUNCE* announce.txt AUTHORS* BACKGROUND BUGS BUG-REPORTING bugs.txt BUILD* CHANGELOG Change[Ll]og changelog.txt CHANGES* changes-* CODING* CodingStyle COMMIT* COMPAT* COMPILING* CONFIGURATION CONTRIBUTORS* COPYING* COPYRIGHT* CREDITS DEBUG DEVELOPERS Developers DISCLAIMER EXAMPLE* EXTENSIONS FAQ* FEATURES FILES FUTURE GPL HACKING HISTORY History* HOWTO* IDEAS INCOMPAT* INSTALL* INTRO KDE* KEYS KNOWN* LANGUAGE.HOWTO LANGUAGES LATEST.VER LEGAL LGPL* lgpl-license LICEN[CS]* License license.txt LSM MANIFEST MAPPING MIRRORS NAMING NEWS NOTES NOTICE OChangeLog ONEWS PACKAGING PERMISSIONS PKG-INFO PLATFORMS PORTING PORTING PORTS PROBLEMS QUICKSTART QuickInst README* Read[Mm]e* readme.txt RELEASE* ReleaseNotes* RELNOTES REVISION RFC.* ROADMAP Road[Mm]ap SOURCE SPONSORS STATUS THANKS THREADS TIPS TODO* ToDo todo.txt TRANSLATING TRANSLATORS TROUBLE* UPGRADING USING VERIFYING VERSION* WHATSNEW WHATS_NEW WhatsNew Y2KINFO $pkgname.[A-Z][A-Z]* $pkgname.spec $pkgname.lsm "$extra_doc_files" $destdir/$docdir 2>/dev/null

    [ "$extra_doc_dirs" ] && cp -auv $extra_doc_dirs $destdir/$docdir
    [ "$doc_subdir" ] && popd
  fi

  popd

  # Generate the slack-desc, slack-required, and slack-suggests files.
  if [ "$pkgconfig" ]; then
    gen_slack_desc "$pkgconfig" "$pkgsummary" >$destdir/install/slack-desc
    for cfgsect in "slack-required" "slack-suggests"; do
      cfgval=$(get_config_section "$pkgconfig" "$cfgsect")
      [ "$cfgval" ] && echo "$cfgval" >$destdir/install/$cfgsect
    done
  fi

  # Copy any files with the name $pkgname.slack-<something> to the install
  # directory.  slack-readme and slack-doinst are exceptions.
  for f in $pkgname.slack-*; do
    b=`echo $f | sed "s;$pkgname\.;;"`
    dest=$destdir/install/$b
    make_exec=0
    case $b in
      slack-readme) dest=$destdir/$docdir/README.Slackware ;;
      slack-doinst) dest=$destdir/$DOINST; make_exec=1 ;;
    esac
    cp $f $dest
    [ $make_exec -eq 1 ] && chmod 755 $dest
  done

  [ -f $pkgname.files.tgz ] && tar xvf $pkgname.files.tgz -C $destdir

  pushd $destdir

  exec_cfg_cmds "$pkgconfig" "post-install" || exit 1
  exec_var_cmds "$post_install_cmds" "Post-install" || exit 1

  popd

fi

# END OF STAGE 4


#########################################
# STAGE 5: prepare files for packaging
#########################################

if [ $skip_prepare_stage -eq 0 ]; then

  echo "STAGE 5: Prepare the files for packaging"

  pushd $destdir || exit 1

  if [ -d usr/share/man -a $fix_man_location -eq 1 ]; then
    if [ -d usr/man ]; then
      mv usr/share/man/* usr/man/
      rmdir -p usr/share/man
    else
      mv usr/share/man usr/
      rmdir usr/share/
    fi
  fi

  if [ -d $docdir ]; then
    find $docdir -size 0 -exec rm {} \; -print
    pushd $docdir/
    # Confirm that there is at least one file.  If not, create one.
    fcount=`ls -1 | wc -l`
    if [ $fcount -eq 0 ]; then
      echo "There are no doc files in $docdir/, creating one..." >&2
      {
        echo "Package: $pkgname"
        echo "Version: $pkgversion"
        echo ""
        echo "This README file was created by $PKGR_NAME ($PKGR_EMAIL)"
        echo "because no documentation was found within this package."
      } > README
    fi
    chmod -R go+r-w .
    popd
  fi

  # Look for any files that are not owner/group root:root.  Skip any
  # files/directories that have the setuid or setgid bit set.  
  echo "Chowning files whose uid/gid are not 0 (but skipping setuid/gid files)"
  find . -not \( -uid 0 -and -gid 0 \) -not -perm -4000 -not -perm -2000 -exec chown root.root {} \; -print

  if [ $chgrp_bin -eq 1 ]; then
    for d in bin sbin usr/bin usr/sbin usr/X11R6/bin ]; do
      if [ -d $d/ ]; then
        chgrp -R root.bin $d
      fi
    done
  fi

  # Standard directories to strip are:
  #   bin/, sbin/, lib/, usr/bin/, usr/sbin/, usr/lib/, usr/libexec/,
  #   opt/kde/bin/, opt/kde/lib/, usr/X11R6/bin/, usr/X11R6/lib/
  # However, we no longer target these directories.  Instead, all ELF files
  # are stripped automatically.

  if [ $strip_elfs -eq 1 ]; then
    if strip_elfs_in_dirs . ; then
      if [ "$pkgarch" = "noarch" ]; then
        echo "$PROG: WARNING: ELF files found in a NOARCH package" >&2
      fi
    else
      if [ "$pkgarch" != "noarch" ]; then
        echo "$PROG: WARNING: No ELF files found in package; consider NOARCH" >&2
      fi
    fi
  fi

  [ "$specific_strip_dirs" ] && strip_elfs_in_dirs "$specific_strip_dirs"


  [ -d usr/man/ ] && find usr/man -type f -exec gzip {} \; -print
  [ -d usr/X11R6/man/ ] && find usr/X11R6/man -type f -exec gzip {} \; -print
  [ -d opt/kde/man/ ] && find opt/kde/man -type f -exec gzip {} \; -print

  if [ -d usr/info/ ]; then
    rm -f usr/info/dir
    gzip usr/info/*
    cat <<EOF >> $DOINST
# Install the info files for this package
if [ -x /usr/bin/install-info ]; then
   /usr/bin/install-info --info-dir=/usr/info /usr/info/$pkgname.info.gz 2>/dev/null
fi
EOF
  fi

  new_files=
  for d in etc/ $extra_new_dirs; do
    if [ -d $d ]; then
      cur_new_files=`find $d -type f -name "*.new"`
      [ "$cur_new_files" ] && new_files="$new_files $cur_new_files"
    fi
  done

  if [ "$new_files" ]; then
    generate_config_installer_func > $DOINST.tmp
    echo "# Handle the installation of config files." >> $DOINST.tmp
    for cf in $new_files; do
      echo "install_config_file $cf" >> $DOINST.tmp
    done

    # Prepend the "new files" scripting to any current doinst scripting.
    [ -f $DOINST ] && cat $DOINST >> $DOINST.tmp
    mv $DOINST.tmp $DOINST
  fi

  if [ "$setup_script" ]; then
    echo "# Run the setup script for this package" >> $DOINST
    echo "echo Running $setup_script" >> $DOINST
    echo "$setup_script" >> $DOINST
  fi

  # Convert symlinks with absolute paths within $destdir to be relative.
  absolute_to_relative $destdir

  # Locate bad symlinks, and report on them.  For broken man page symlinks
  # (which occurs due to the gzipping of the man pages), recreate them.
  find_broken_symlinks

  exec_cfg_cmds "$pkgconfig" "post-prepare" || exit 1
  exec_var_cmds "$post_prepare_cmds" "Post-prepare" || exit 1

  popd
fi

# END OF STAGE 5


#########################################
# STAGE 6: create and check the package
#########################################

if [ $skip_pkg_stage -eq 1 ]; then
  echo "$PROG: Stopping after installation but before package generation"
  exit 0
fi

echo "STAGE 6: Create the package and check its integrity"

pushd $destdir

exec_cfg_cmds "$pkgconfig" "pre-package" || exit 1
exec_var_cmds "$pre_package_cmds" "Pre-package" || exit 1

# First, determine the name of the resulting package, properly generating
# the release number.

cd $pkg_archive || exit 1

pkgbase_arch=$pkgbase-${pkgarch}
if [ $lowercase -eq 1 ]; then
  pkgbase_arch=`echo $pkgbase_arch | tolowercase`
fi

# Since ls sorts the output, get the highest-numbered release.
# Note: Only releases from 1-9 are supported.
max_rel=`ls -1 ${pkgbase_arch}-[0-9]$PKGR_INITS.$PKG_EXT 2>/dev/null | tail -1 | sed -e "s;${pkgbase_arch}-;;" -e "s;$PKGR_INITS.$PKG_EXT;;"`

if [ "$max_rel" ]; then
  pkg_release=`expr $max_rel + 1`
else
  pkg_release=1
fi

cd $destdir

full_pkg_file=$pkg_archive/${pkgbase_arch}-${pkg_release}$PKGR_INITS.$PKG_EXT

$PKG_CMD $PKG_STD_OPTS $full_pkg_file

pkgcheck.pl $full_pkg_file

exec_cfg_cmds "$pkgconfig" "post-package" || exit 1
exec_var_cmds "$post_package_cmds" "Post-package" || exit 1

popd

# END OF STAGE 6

exit 0
