#!/bin/sh
#

prog=`basename $0`
f1=
f2=
level=1

usage() {
  echo "Usage: $prog [-p level] tarfile1 {tarfile2 | dir}" >&2
}


if [ $# -lt 1 ]; then
  usage
  exit 1
fi

while [ $# -gt 0 ]; do
  case "$1" in
    -p) shift; level="$1" ;;
    -*) echo "$prog: $1: Unknown option" >&2; usage; exit 1 ;;
    *) [ $f1 ] && f2="$1" || f1="$1"
  esac
  shift
done

if [ ! "$f1" -o ! "$f2" ]; then
  usage
  exit 1
elif [ ! -f "$f1" ]; then
  echo "$prog: $f1: File not found" >&2
  exit 1
elif [ -d "$f2" ]; then
  f2="$f2/$f1"
elif [ ! -f "$f2" ]; then
  echo "$prog: $f2: File not found" >&2
  exit 1
fi

for i in 1 2; do
  outfile="/tmp/f${i}_sorted.out"
  eval f${i}_outfile="$outfile"
  eval fvar=f$i
  f=${!fvar}

  case $f in
    *.tar) decompress="cat" ;;
    *.tar.gz|*.tgz) decompress="gunzip -c" ;;
    *.tar.bz2|*.tbz2) decompress="bunzip2 -c" ;;
    *.tar.xz|*.txz) decompress="xz -d -c" ;;
    *) echo "$prog: $f: Unknown archive type" >&2; exit 1 ;;
  esac

# tar now supports auto-decompression
#  $decompress $f | tar t | sort | cut -d/ -f${level}- > $outfile
  tar tf $f | sort | cut -d/ -f${level}- > $outfile
done

#tar ztf $f1 | sort > $f1_outfile
#tar ztf $f2 | sort > $f2_outfile

diff $f1_outfile $f2_outfile
rm -f $f1_outfile $f2_outfile
exit 0
