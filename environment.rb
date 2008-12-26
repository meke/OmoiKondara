#!/usr/bin/env ruby19
# $Id: environment.rb,v 1.6 2003/10/22 14:47:37 kazuhiko Exp $

# $ rd2 -rrd/rd2man-lib <this_file> | nroff -man

=begin
= NAME
environment.rb - Sets up environment for momonga tools.
= SYNOPSIS
: In Ruby scripts
  At the beginning of the script, do
   $:.unshift File.dirname($0)
   load 'environment.rb'
: In Shell scripts
  At the beginning of the script, do
   PATH=`dirname $0`:$PATH
   eval `environment.rb`
= DESCRIPTION
((*environment.rb*)) sets up commonly used variables for Momonga's
building tools.

Currently, following variables are set. Symbols in left and right of a
slash('/') is for Shell scripts and Ruby scripts, respectively.

: (({ARCH})) / (({$ARCH}))
  Target architecture.
: (({TOPDIR})) / (({$TOPDIR}))
  Output top directory.
: (({PKGDIR})) / (({$PKGDIR}))
  Location of pkg CVS module.
: (({FTP_CMD})) / (({$FTP_CMD}))
  An external ftp command to be used.
: (({DISPLAY})) / (({$DISPLAY}))
  X server connection.
: (({MAILADDR})) / (({$MAILADDR}))
  Email address for anonymous ftp.
: (({DISTCC_VERBOSE})) / (({DISTCC_VERBOSE}))
  Distcc verbosity.
: (({NUMJOBS})) / (({$NUMJOBS}))
  Number of jobs.
: (({WORKDIR})) / (({$WORKDIR}))
  Working directory.
: ((*not available*)) / (({DISTCC_HOST}))
  List of distcc hosts.
: ((*not available*)) / (({URL_ALIAS}))
  List of URL rewriting rules.
: ((*not available*)) / (({$MIRROR}))
  List of mirror servers for source fetching.
: (({GPGSIGN})) / ((${GPGSIGN}))
  Embed a GPG signature.
Other variables will be added in the future.
= OPTIONS
None.
= AUTHOR
Written by OZAWA -Crouton- Sakuro <crouton@momonga-linux.org>
= BUG
Reports and enhancements are welcome.
=end
#'

$TOPDIR = nil
$PKGDIR = nil
$MIRROR = []
$DISTCC_HOSTS = []
$URL_ALIAS = {}

$CONF_FILES = %w(./.OmoiKondara ~/.OmoiKondara /etc/OmoiKondara.conf)

found_conf = false
$CONF_FILES.each do |conf|
  conf = File.expand_path(conf)
  next unless FileTest.exist?(conf)
  found_conf = true
  open(conf) do |f|
    f.each_line do |line|
      next  if line =~ /^#.*$/ or line =~ /^$/
      s = line.split
      v = s.shift
      v.upcase!
      case v
      when "TOPDIR"
	$TOPDIR = s.shift
      when "PKGDIR"
	$PKGDIR = s.shift
      when "MIRROR"
	while v = s.shift
	  $MIRROR << v
	end
      when "FTP_CMD"
	$FTP_CMD = s.join " "
      when "DISPLAY"
	$DISPLAY = s.join " "
      when "URL_ALIAS"
	$URL_ALIAS[Regexp.compile(s.first)] = s.last
      when "DISTCC_HOST"
	$DISTCC_HOSTS.push s.last if not $DISTCC_HOSTS.include?(s.last)
      when "DISTCC_VERBOSE"
	$DISTCC_VERBOSE = true
      when "NUMJOBS"
	$NUMJOBS = s.shift
      when "WORKDIR"
	$WORKDIR = s.shift
	if not File.directory?($WORKDIR) then
	  $stderr.puts "WARNING: invalid workdir. use default"
	  $WORKDIR = nil
	end
      when "GPGSIGN"
        $GPGSIGN = true
      end
    end
  end
  break
end

if found_conf == false
  $stderr.puts <<EOF
FATAL: .OmoiKondara not found.
F.Y.I: please copy tools/example.OmoiKondara to pkgs/.OmoiKondara
       and modify that.
EOF
  exit 1
end

%w(TOPDIR PKGDIR).each do |name|
  if eval('$' + name) == nil
    $stderr.puts "FATAL: Mandatory parameter #{name} is not set."
    exit 1
  end
end

$TOPDIR = File.expand_path $TOPDIR
$PKGDIR = File.expand_path $PKGDIR

$ARCH = `uname -m`.chomp

case $ARCH
when 'x86_64'
  $NOTFILE = 'NOT.x86_64'
  $ARCH = 'x86_64'
when /^i\d86$/
  $NOTFILE = 'NOT.ix86'
  $ARCH = 'i686'
when /^alpha/
  $NOTFILE = 'NOT.alpha'
  open('/proc/cpuinfo').readlines.each do |line|
    if line =~ /^cpu model\s*:\s*EV([0-9]).*$/ && $1 == '5'
      $ARCH = 'alphaev5'
      break
    end
  end
when 'mips'
  $NOTFILE = 'NOT.mips'
  open('/proc/cpuinfo').readlines.each do |line|
    if line =~ /^cpu model\s*:\s*R5900.*/
      $ARCH = 'mipsel'
      break
    end
  end
when /^ppc64/
  $NOTFILE = 'NOT.ppc64'
  $ARCH = 'ppc64'
when /^ppc/
  $NOTFILE = 'NOT.ppc'
  $ARCH = 'ppc'
when /^ia64/
  $NOTFILE = 'NOT.ia64'
  $ARCH = 'ia64'
else
  $stderr.puts %Q(WARNING: unsupported architecture #{$ARCH})
end

found_rpmvercmp = false
found_ftp_cmd = false
ftp_cmd_name = $FTP_CMD.split[0]
"#{ENV['PATH']}:../tools/v2".split(/:/).each do |path|
  path = File.expand_path(path)
  if found_rpmvercmp == false && FileTest.exist?("#{path}/rpmvercmp")
    found_rpmvercmp = true
  end
  if found_ftp_cmd == false && FileTest.exist?("#{path}/#{ftp_cmd_name}")
    found_ftp_cmd = true
  end
end
if found_rpmvercmp == false
  $stderr.puts "FATAL: rpmvercmp not found."
  $stderr.puts "F.Y.I: please svn update"
  exit 1
end
if found_ftp_cmd == false
  $stderr.puts "FATAL: #{ftp_cmd_name} not found."
  $stderr.puts "F.Y.I: please install #{ftp_cmd_name}."
  exit 1
end

if $0 == __FILE__
  %w(TOPDIR PKGDIR FTP_CMD DISPLAY MAILADDR ARCH DISTCC_VERBOSE NUMJOBS WORKDIR).each do |name|
    puts %Q(#{name}='#{eval('$' + name)}'; export #{name})
  end
end

# [RPM46] check rpmbuild version
def rpm46?
  def rpmbuild_version(maj, min, mic)
    return (maj<<16) + (min<<8) + mic
  end
  v = `LANG=C rpmbuild --version | cut -d' ' -f 3`.chomp!.split(/[\.-]/)
  rpmbuild_version_code = rpmbuild_version(v[0].to_i, v[1].to_i, v[2].to_i)
  return rpmbuild_version(4, 6, 0) <= rpmbuild_version_code
end
