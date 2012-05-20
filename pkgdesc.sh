#!/bin/sh
#

prog=`basename $0`
pkginfodir=/var/adm/packages
srcdir=/usr/local/src
slackver=`slackver.sh`
pkgdir=/usr/local/Slackware/$slackver
myname=ken

if [ $# -ne 1 ]; then
  echo "Usage: $prog package_name" >&2
  exit 1
fi

pkgnamepre="$1"

cd $pkginfodir

pkglist=`ls $pkgnamepre* 2>/dev/null`

if [ ! "$pkglist" ]; then
  echo "$prog: No package whose name begins with '$pkgnamepre' is installed" >&2
  exit 1
fi

for f in $pkglist; do
  pkgfile=$f.tgz
  pkgdesc=`cat $f | sed "1,/^PACKAGE DESCRIPTION/d" | sed '/^FILE LIST/,$d'`
  pkgname=`echo "$pkgdesc" | head -1 | egrep -o '^[^:]+'`
  pkgrelpath=`cd $pkgdir; find . -name $pkgfile | sed "s;^\./;;"`
  pkgpath="$pkgdir/$pkgrelpath"
  urlpath="$myname/$pkgrelpath"

  if [ ! "$pkgpath" ]; then
    echo "$prog: $pkgname: Not found in $pkgdir" >&2
    continue
  fi

  size=`stat -c %s $pkgpath`
  md5sum=`md5sum $pkgpath | cut -d" " -f1`
  slackdesc=`find $srcdir -maxdepth 3 -iname $pkgname.slack-desc`

  if [ "$slackdesc" ]; then
    readme=`echo $slackdesc | sed "s;\.slack-desc$;.README;"`
    if [ -r "$readme" ]; then
      url=`grep -m 1 "^URL" $readme | sed "s;[^=:]*[=:];;"`
      license=`grep -m 1 "^LICENSE" $readme | sed "s;[^=:]*[=:];;"`
    fi
    slackreq=`echo $slackdesc | sed "s;-desc$;-required;"`
    if [ -r "$slackreq" ]; then
      required=`cat $slackreq`
    else
      required="Unknown requirements"
    fi
  else
    url="Unknown"
    license="Unknown"
    required="Unknown"
  fi

  echo "-----------------------"
  echo "NAME: $pkgname"
  echo "FILE: $pkgfile"
  echo "HTTP: http://www3.linuxpackages.net/packages/Slackware/Slackware-$slackver/$urlpath"
  echo "FTP: ftp://ftp.linuxpackages.net/pub/Slackware/Slackware-$slackver/$urlpath"
  echo "META: $urlpath"
  echo "SIZE: $size"
  echo "MD5SUM: $md5sum"
  echo "URL: $url"
  echo "LICENSE: $license"

  echo

  echo "$pkgdesc" | sed "s;^[^:]*: *;;" | sed '1,3s;^$;<br/><br/>;'

  echo
  echo "REQUIRES:"
  echo "$required"
done

exit 0
