#!/usr/bin/perl 

# Copyright 2004  Mark Tucker (mark@tucker.net)
# All rights reserved.
#
# Redistribution and use of this script, with or without modification, is
# permitted provided that the following conditions are met:
#
# 1. Redistributions of this script must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
#  THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
#  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
#  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO
#  EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
#  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
#  OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
#  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
#  OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
#  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# pkgcheck.pl
#
# VERSION 1.0.1
#
# Script to check a slackware package for common (and, hopefully, uncommmon 
# errors. The following checks are made:
#  - package naming.
#  - set UID files
#  - "./" directory exists in package
#  - the "install" dir exists
#  - slack-desc file exists.
#  - contents of slack-desc file (checks that there is something there)
#  - non-root owned files
#  - bin directories and files are group "bin"
#  - bin files are executable
#  - zero length files
#  - non-readable files
#  - non-readable directories
#  - existance of documentation directory (and that it matches the package name)
#  - documentation directory at /usr/share/doc
#  - empty documentation directory
#  - man directory in /usr/share/man
#  - non-compressed man pages
#  - non-compressed info pages
#  - existance of info dir or dir.gz file
#  - existance of /usr/etc directory
#  - existance of /usr/local directory
#  - abnormally large files

#  Comments, problems or suggestions can be sent to mark@tucker.net
#

#  CHANGES:
#     Jul 23, 2004 - initial creation
#     Sep 8, 2004  - added "noarch" as a valid arch type
#                  - added check for /usr/share/man
#                  - added check for /usr/share/doc
#============================================================================
# set vars and paths
@bindirs = ('usr/bin/', 'bin/', 'sbin/', 'usr/sbin/', 'usr/X11R6/bin/');

# parse arguments (if any)
if(! defined @ARGV) {
    print "You must provide the name of a package to test\n";
    print "\nUsage:\n\t$0 pkg_name-ver-arch-rel.{tgz,txz}\n\n";
    exit;
}else{
    chomp($PKG = $ARGV[0]);
}




###################################################
# check package naming
###################################################
chomp($filename = `basename $PKG`);
print "Checking package: $filename\n";
@pkg_nam = split(/-/, $filename);

#----------------
# ends w/ .tgz
#----------------
print "Checking file name extension (.tgz or .txz)... ";
if($filename !~ /\.t[gx]z$/) {
    print "\n\nERROR: package is not a compressed tar archive or is not "
	."properly named.  Exiting...\n";
    exit;
}else{
    print "OK\n";
}

#----------------
# has #xxx release name
#----------------
print "Checking package name release... ";
$testok = 1;
($pkg_rel, $junk) = split(/\./, $pkg_nam[$#pkg_nam]);
if($pkg_rel !~ /^[0-9]/) {
    print "\nERROR: package release must indicate a number value.\n";
    $testok = 0;
}
if($pkg_rel !~ /[a-z]$/) {
    print "\nERROR: package release must contain more than just the number.\n";
    $testok = 0;
}

if($testok == 1) {
    print "$pkg_rel\n";
}else{
    exit;
}

#----------------
# check for valid arch (i386 -> i686)
#----------------
print "Checking package arch... ";
$pkg_arch = $pkg_nam[($#pkg_nam - 1)];
if($pkg_arch =~ /(i[3456]86)|x86_64|s390|arm|noarch/) {
    print "$pkg_arch\n";
}else{
    &err_fatal("\nERROR: package arch, $pkg_arch, is not a valid value.");
}

#----------------
# store version field
#----------------
print "Checking package version... ";
$pkg_ver = $pkg_nam[($#pkg_nam - 2)];
print "$pkg_ver\n";

#---------------- 
# store package name
#----------------
print "Checking package name... ";
if($#pkg_nam > 3) {
    $pkg_name = join('-', @pkg_nam[0..($#pkg_nam - 3)]);
}else{
    $pkg_name = $pkg_nam[0];
}
print "$pkg_name\n";

#----------------
# store package-ver name
#----------------
$pkg_name_ver = "$pkg_name-$pkg_ver";

###################################################
# read the contents of the package
###################################################
print "Reading the contents of the package... \n";
chomp(@package = `tar -tvf $PKG`);

#--------------------------------------------------
# create hashes for each line element
#--------------------------------------------------
foreach $k (@package) {
#    print "$k\n";
    my @line = split(/\s+/, $k);
    $name = $line[$#line];
    push(@all_names, $name);

    # create arrays by file type
    push(@dirs, $name) if($k =~ /^d/);
    push(@files, $name) if($k =~ /^-/);
    push(@links, $name) if($k =~ /^l/);

    # store permissions by name
    $perms{$name} = $line[0];
    $filetype = substr($perms{$name}, 0, 1);
    $perms_owner{$name} = substr($perms{$name}, 1, 3);
    $perms_group{$name} = substr($perms{$name}, 4, 3);
    $perms_other{$name} = substr($perms{$name}, 7, 3);
   
    # store owner,group by name
    ($owner{$name},$group{$name}) = split(/\//, $line[1]);

    # store file/dir size by name
    $size{$name} = $line[2];
    
}


###################################################
# specific checks....
###################################################
#--------------------------------------------------
# check for suid files
#--------------------------------------------------
print "Checking setuid files... ";
$testok = 1;
foreach $k (@files) {
    if($perms_owner{$k} =~ /s$/) {
	&err_fatal("Permissions for $k are SUID");
	$testok = 0;
    }
}
print "OK\n" if($testok == 1);

#--------------------------------------------------
# check for "./" dir
#--------------------------------------------------
print "Checking for proper root directory... ";
$testok = 0;
foreach $k (@dirs) {
    if($k eq './') {
	print "OK\n";
	$testok = 1;
	last;
    }
}
if($testok == 0) {
    print "Error\n";
    &err_fatal("'./' directory entry missing from package.");
}


#--------------------------------------------------
# check for ./install dir
#--------------------------------------------------
print "Checking for './install' directory... ";
$testok = 0;
foreach $k (@dirs) {
    if($k eq 'install/') {
	print "OK\n";
	$testok = 1;
	last;
    }
}
if($testok == 0) {
    &err_fatal("'install/' directory entry missing from package.");
}


#--------------------------------------------------
# check for slack-desc file
#--------------------------------------------------
print "Checking for slack-desc file... ";
$testok = 0;
foreach $k (@files) {
    if($k eq 'install/slack-desc') {
	print "OK\n";
	$testok = 1;
    }
}
if($testok == 0) {
    &err_fatal("'slack-desc' file is missing from package.");
}else{
#--------------------------------------------------
# check slack-desc file contents
#--------------------------------------------------
# kennyz - added pkg_name_pat with escaped '+' chars, since some
# package names can have '+' in them

    ($pkg_name_pat = $pkg_name) =~ s/[+]/[+]/g;

    print "Checking contents of slack-desc file... ";
    $testok = 0;

    #  dump contents to array 
    chomp(@slkdsc = `tar -xOf $PKG install/slack-desc`);

    #--------------------
    # check for pkg_name in file
    # There should be more than 1 line starting with the package name.
    #--------------------
    foreach $j (@slkdsc) {
	if($j =~ /^$pkg_name_pat:/) {
	    $count++;
	}
    }
    if($count != 0) {
	$testok = 1;
    }else{
	&err_warn("No lines in slack-desc match the package name, $pkg_name");
    }
    #--------------------
    # check for description lines
    # This just checks that there are at least 2 lines of description which
    # are more than 5 characters in lenght.
    #--------------------
    $count = 0;
    foreach $j (@slkdsc) {
	next if($j !~ /^$pkg_name_pat:/);
	$descr = substr($j, (length($pkg_name) + 2));
	$count++ if(length($descr) > 5);
    }
    if($count > 2) {
	$testok = 1;
    }else{
	&err_warn("slack-desc file seems to be a bit sparse, $count lines.");
    }


    print "OK\n" if($testok == 1);
}


#--------------------------------------------------  
# check for non-root owned files or dirs (report error)
#--------------------------------------------------
print "Checking for non-root owned files and dirs... ";
$testok = 1;
foreach $k (@all_names) {
    if($owner{$k} ne 'root') {
	&err_fatal("$k not owned by the root user");
	$testok = 0;
    }
}
print "OK\n" if($testok == 1);
#--------------------------------------------------
# group=bin for /usr/bin, /bin, /sbin, /usr/sbin, and /usr/X11R6/bin 
#--------------------------------------------------
# kz - 20061008 - this check is no longer necessary as of Slackware 11
#print "Checking group for bin directories... ";
#$testok = 1;
#foreach $k (@all_names) {
#    foreach $j (@bindirs) {
#	if(($k =~ /^$j/) && ($group{$k} ne 'bin')) {
#	    $testok = 0;
#	    &err_warn("$k should have a group of 'bin'");
#	}
#    }
#}
#print "OK\n" if($testok == 1);

#--------------------------------------------------
# check bin dirs for non-executable files
#--------------------------------------------------
print "Checking bin files for execute permissions... ";
$testok = 1;

foreach $k (@files) {
    foreach $j (@bindirs) {
	if($k =~ /^$j/) {
	    $count = 0;
	    $count++ if($perms_owner{$k} =~ /x$/);
	    $count++ if($perms_group{$k} =~ /x$/);
	    $count++ if($perms_other{$k} =~ /x$/);
	    if($count == 0) {
		&err_warn("No execute permissions for $k");
		$testok = 0;
	    }

	}
    }
}
print "OK\n" if($testok == 1);

#--------------------------------------------------
# check for zero length files
#--------------------------------------------------
print "Checking zero length files... ";
$testok = 1;
foreach $k (@files) {
    if($size{$k} == 0) {
	if($k =~ /^install\//) {
	    &err_warn("file $k has zero length, using checkinstall, eh?");
	}else{
	    &err_suggest("file $k has zero length, this could be a problem.");
	}
	$testok = 0;
    }
}
print "OK\n" if($testok == 1);
	
#--------------------------------------------------
# check for non-readable files
#--------------------------------------------------
print "Checking non readable files... ";
$testok = 1;
foreach $k (@files) {
    $count = 0;
    $count++ if($perms_owner{$k} !~ /^r/);
    $count++ if($perms_group{$k} !~ /^r/);
    $count++ if($perms_other{$k} !~ /^r/);
    if($count != 0) {
	&err_suggest("File $k has no read permssions");
	$testok = 0;
    }
}
print "OK\n" if($testok == 1);


#--------------------------------------------------
# check for non-readable directories
#--------------------------------------------------
print "Checking non readable directories... ";
$testok = 1;
foreach $k (@dirs) {
    $count = 0;
    $count++ if($perms_owner{$k} !~ /^r.x$/);
    $count++ if($perms_group{$k} !~ /^r.x$/);
    $count++ if($perms_other{$k} !~ /^r.x$/);
    if($count != 0) {
	&err_suggest("Directory $k has no read permssions");
	$testok = 0;
    }
}
print "OK\n" if($testok == 1);

#--------------------------------------------------
# check for usr/doc/pkg_ver 
#--------------------------------------------------
# kennyz - added $pkg_name_ver_pat, with substitutions for '+', since
# some package names have '+' in them.
print "Checking for documentation directory... ";
($pkg_name_ver_pat = $pkg_name_ver) =~ s/[+]/[+]/g;
$testok = 0;
foreach $k (@dirs) {
    if(($k =~ /usr\/doc\/$pkg_name_ver_pat/) ||
	($k =~ /usr\/share\/doc\/$pkg_name_ver_pat/)) {
	$testok = 1;
    }
}
if($testok == 0) {
    &err_fatal("Missing documentation directory /usr/doc/$pkg_name_ver");
}else{
    print "OK\n";
}

#--------------------------------------------------
# check for usr/doc/pkg_ver or usr/share/doc/pkg_ver
#--------------------------------------------------
print "Checking for documentation directory in /usr/share... ";
$testok = 1;
foreach $k (@dirs) {
    if($k =~ /usr\/share\/doc\/$pkg_name_ver_pat/) {
	$testok = 0;
    }
}
if($testok == 0) {
    &err_warn("Found documentation directory /usr/share/doc/, should be /usr/doc/");
}else{
    print "OK\n";
}


#--------------------------------------------------
# check for files in usr/doc/pkg_ver or usr/share/doc/pkg_ver
#--------------------------------------------------
print "Checking for empty documentation directory... ";
$testok = 0;
$count = 0;
foreach $k (@files) {
    $count++ if($k =~ /usr\/doc\/$pkg_name_ver_pat/);
    $count++ if($k =~ /usr\/share\/doc\/$pkg_name_ver_pat/);
}
if($count == 0) {
    &err_fatal("There are no files in usr/doc/$pkg_name_ver");
}else{
    print "OK\n";
}

#--------------------------------------------------
# check for usr/share/man directory
#--------------------------------------------------
print "Checking for /usr/share/man... ";
$testok = 1;
foreach $k (@dirs) {
    if($k =~ /usr\/share\/man/) {
	$testok = 0;
    }
}
if($testok == 0) {
    &err_warn("Man directory found in /usr/share/man - Would be better as /usr/man");
}else{
    print "OK, not found.\n";
}


#--------------------------------------------------
# check for gzipped man pages
#--------------------------------------------------
# kennyz - modified pattern to handle other cases besides /usr/man/manXXX
# such as /usr/man/de/manX
print "Checking non-compressed man pages... ";
$testok = 1;
foreach $k (@files) {
    if($k =~ /\/man(\/[^\/]+)?\/man.*[1-9]$/) {
	&err_warn("man page $k should be compressed");
	$testok = 0;
    }
}
print "OK\n" if($testok == 1);

#--------------------------------------------------
# check for gzipped info pages
#--------------------------------------------------
print "Checking non-compressed info pages... ";
$testok = 1;
foreach $k (@files) {
    if(($k =~ /usr\/info\//) && ($k !~ /gz$/) &&
	($k !~ /dir/)) {
	&err_warn("info page $k should be compressed");
	$testok = 0;
    }
}
print "OK\n" if($testok == 1);

#--------------------------------------------------
# check for  info dir or dir.gz file (report error)
#--------------------------------------------------
print "Checking for info dir or dir.gz... ";
$testok = 1;
foreach $k (@files) {
    if($k =~ /info\/dir/) {
	&err_suggest("File $k will overwrite the user's info dir file.");
	$testok = 0;
    }
}
print "OK\n" if($testok == 1);
    
#--------------------------------------------------
# check for /usr/etc dir and files (report error)
#--------------------------------------------------
print "Checking for usr/etc/ directory... ";
$testok = 1;
foreach $k (@dirs) {
    if($k =~ /^usr\/etc\//) {
	&err_fatal("Directory $k should not exist, use /etc.");
	$testok = 0;
    }
}
print "OK\n" if($testok == 1);

#--------------------------------------------------
# check for /usr/local/ dir (report error)
#--------------------------------------------------
print "Checking for usr/local/ directory... ";
$testok = 1;
foreach $k (@dirs) {
    if($k =~ /^usr\/local\//) {
	&err_fatal("Directory $k should not exist.");
	$testok = 0;
    }
}
print "OK\n" if($testok == 1);

#--------------------------------------------------
# check for unusually large files..
#--------------------------------------------------
print "Checking for abnormally large files... ";
$testok = 1;
foreach $k (@files) {
    if($size{$k} > 10000000) {
	&err_suggest("File $k has a size of $size{$k}, you may want to run the 'strip' utility on it.");
	$testok = 0;
    }
}
print "OK\n" if($testok == 1);

###################################################
# report errors
###################################################
print "-" x 60 ."\n";

# print fatal errors
print "\nFATAL ERRORS:\n";
foreach $i (@fatal_errors) {
    print "\t$i\n";
}
    
# print warnings
print "\nWARNINGS:\n";
foreach $i (@warnings) {
    print "\t$i\n";
}

# print suggestions
print "\nSUGGESTIONS:\n";
foreach $i (@suggestions) {
    print "\t$i\n";
}

# print summary
print "-" x 60 ."\n";
print "SUMMARY for $filename:";
print "\n".($#fatal_errors + 1).
    " fatal errors.\n".($#warnings + 1)." warnings.\n".
    ($#suggestions + 1)." suggestions\n";
print "-" x 60 ."\n";
exit;
###################################################
# sub routines
###################################################
#==================================================
sub err_fatal {
    print "  Error.\n";
    push(@fatal_errors, $_[0]);
}
#==================================================
sub err_warn {
    print "  Warning.\n";
    push(@warnings, $_[0]);
}
#==================================================
sub err_suggest {
    print "OK.\n";
    push(@suggestions, $_[0]);
}
