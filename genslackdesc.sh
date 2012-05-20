#!/bin/sh
#
# genslackdesc.sh - Generate a Slackware slack-desc file in proper format
#
# Written by Ken Zalewski
# First release on 2012-04-05
# Last revised on 2012-04-12
#

prog=`basename $0`
MAX_PKGNAME_LEN=40
MAX_SCREEN_WIDTH=80
MAX_DESC_WIDTH=72
MAX_LINE_COUNT=11

usage() {
  echo "Usage: $prog [-h] [-f] [-i infile] [-L lines] [-l] [-n pkgrName] [-e pkgrEmail] [-o outfile] [-s pkgSummary] [-u pkgUrl] [-v pkgVersion] [-w width] pkgName" >&2
}

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

pkgremail=
inc_footer=0
inc_header=0
infile=
line_count=$MAX_LINE_COUNT
lowercase=0
pkgrname=
outfile=
pkgsummary=
pkgurl=
pkgversion=
max_desc_width=$MAX_DESC_WIDTH
pkgname=

while [ $# -gt 0 ]; do
  case "$1" in
    -e|--pkgremail) shift; pkgremail="$1" ;;
    -f|--footer) inc_footer=1 ;;
    -h|--header) inc_header=1 ;;
    -i|--infile) shift; infile="$1" ;;
    -L|--lines) shift; line_count="$1" ;;
    -l|--lowercase) lowercase=1 ;;
    -n|--pkgrname) shift; pkgrname="$1" ;;
    -o|--outfile) shift; outfile="$1" ;;
    -s|--pkgsummary) shift; pkgsummary="$1" ;;
    -u|--url) shift; pkgurl="$1" ;;
    -v|--pkgversion) shift; pkgversion="$1" ;;
    -w|--width) shift; max_desc_width="$1" ;;
    -*) echo "$prog: $1: Invalid option" >&2; usage; exit 1 ;;
    *) pkgname="$1" ;;
  esac
  shift
done

if [ ! "$pkgname" ]; then
  echo "$prog: Must specify a package name" >&2
  exit 1
elif [ $lowercase -eq 1 ]; then
  declare -l pkgidxname
fi

pkgidxname="$pkgname"
pkgname_len=${#pkgname}

if [ $pkgname_len -gt $MAX_PKGNAME_LEN ]; then
  echo "$prog: $pkgname: Package name is longer than $MAX_PKGNAME_LEN characters" >&2
  exit 1
elif [ $inc_footer -eq 1 -a ! "$pkgrname" ]; then
  echo "$prog: Must specify a packager name [-n] when using a footer" >&2
  exit 1
fi

desc_width=$(($MAX_SCREEN_WIDTH - $pkgname_len - 2))
[ $desc_width -gt $max_desc_width ] && desc_width=$max_desc_width
line_length=$(($pkgname_len + 2 + $desc_width))

ruler="|"
for ((i=1; i<=$desc_width; i++)); do
  ruler+="-"
done
ruler+="|"

line_count=$(($line_count - $inc_header - $inc_footer))

printf "%${pkgname_len}s%s\n" " " "$ruler"

if [ $inc_header -eq 1 ]; then
  { echo -n "$pkgname: $pkgname"
  [ "$pkgversion" ] && echo -n " $pkgversion"
  [ "$pkgsummary" ] && echo -n " ($pkgsummary)"
  } | cut -c -$line_length
fi

cat $infile | \
sed -e "s;%PKGNAME%;$pkgname;g" -e "s;%PKGVERSION%;$pkgversion;g" \
    -e "s;%PKGRNAME%;$pkgrname;g" -e "s;%PKGREMAIL%;$pkgremail;g" \
    -e "s;%PKGURL%;$pkgurl;g" -e "s;%PKGSUMMARY%;$pkgsummary;g" \
    -e 's;^$;\\n\\n;' | \
tr '\n' ' ' | \
sed -e 's;$;\n;' -e 's; *\\n *;\n;g' | \
fold -s -w $desc_width | \
sed "s;^;$pkgidxname: ;" | \
sed 's;  *$;;' | \
head -n $line_count

if [ $inc_footer -eq 1 ]; then
  echo -n "$pkgname: Packaged by $pkgrname"
  [ "$pkgremail" ] && echo -n " ($pkgremail)"
  echo
fi

exit 0
