# -*- coding: utf-8 -*-

#
# 定数

# buildme(), chk_requires(), build_and_install() などの返り値
#
MOMO_SUCCESS  =  0  #  ビルド成功
MOMO_SKIP     =  1  #  SKIP
MOMO_FAILURE  =  2  #  失敗
MOMO_OBSOLETE =  3  #  OBSOLETE
MOMO_LOOP     =  4  #  依存関係にループがあったため失敗
MOMO_CHECKSUM =  5  #  ファイルのチェックサムが間違っている
MOMO_NOTFOUND =  6  #  ファイルのダウンロードに失敗した
MOMO_BUILDREQ =  7  #  BuildReqしているパッケージが用意できなかった
MOMO_SIGINT   =  8  #  sigint で中断された
MOMO_NO_SUCH_PACKAGE = 10  # パッケージが存在しない
MOMO_UNDEFINED  = 999 # 内部エラー状態

# configration系
#
#
def parse_conf
  $CONF_FILES.each do |conf|
    conf = File.expand_path conf
    next  unless File.exist?(conf)
    IO.foreach(conf) do |line|
      line.strip!
      next  if line =~ /^#.*$/ or line =~ /^$/
      s = line.split(/\s+/, 2)
      v = s.shift
      v.upcase!
      case v
      when "TOPDIR"
        $TOPDIR = s.shift
      when "MIRROR"
        while v = s.shift
          $MIRROR += [v]
        end
      when "FTP_CMD"
        $FTP_CMD = s.join " "
      when "DISPLAY"
        $DISPLAY = s.join " "
      when "URL_ALIAS"
        $URL_ALIAS[Regexp.compile(s.first)] = s.last
      when "USE_CACHECC1"
        $GLOBAL_CACHECC1 = true
      when "CACHECC1_DISTCCDIR"
        $CACHECC1_DISTCCDIR = s.shift
        if not File.directory?($CACHECC1_DISTCCDIR) then
          $stderr.puts "WARNING: invalid CACHECC1_DISTCCDIR"
        end
        if not File.executable?("#{$CACHECC1_DISTCCDIR}/distccwrap") then
          $stderr.puts "WARNING: invalid CACHECC1_DISTCCDIR: no distccwrap"
        end
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
      when "LOG_FILE_COMPRESS"
        $LOG_FILE_COMPRESS = false if s.shift == 'false'
      when "COMPRESS_CMD"
        $COMPRESS_CMD = s.shift
      when "CHECKSUM_MODE"
        $CHECKSUM_MODE = s.shift
      when "STORE"
        $STORE = s.shift
      end
    end
    return
  end
end

def show_usage()
  print <<END_OF_USAGE
Usage: ../tools/OmoiKondara [options] [names]
  -A, --arch "ARCH"       specify architecture
  -C, --noccache          no ccache
  -D, --distcc            enable to use distcc
  -F  --force-fetch       force fetch NoSource/NoPatch
  -G, --debug             enable debug flag
  -J, --noswitch-java     not auto switch java environment
  -L, --alter             build Alter(alternative) package, too
  -M, --mirrorfirst       download from mirror first
  -N, --nostrict          proceed by old behavior
  -O, --orphan            build Orphan package, too
  -R, --ignore-remove     do not uninstall packege if REMOVE.* exists
  -S, --scanpackages      execute mph-scanpackage
  -a, --archdep           ignore noarch packages
  -c, --cvs               (ignored. remained for compatibility)
  -d, --depend "DEPENDS"  specify dependencies
  -f, --force             force build
  -g, --checkgroup        group check only
  -i, --install           install after build (except kernel and usolame)
  -m, --main              main package only
  -n, --nonfree           build Nonfree package, too
  -o  --check-only        checksum compare(run "rpmbuild -bp")
  -r, --rpmopt "RPMOPTS"  specify option through to rpm
  -s, --script            script mode
  -v, --verbose           verbose mode
  -z, --zoo               build Zoo package, too
  -1, --cachecc1          use cachecc1
      --checksum "MODE"   checksum mode ("strict", "workaround", "maintainer")
      --forceinstall      force install after build (except kernel and usolame)
      --ftpcmd "FTP_CMD"  set ftp command
      --fullbuild         full build packages and force install after build
      --nodeps            ignore buildreqs
      --noworkdir         do not use WORKDIR
      --numjobs num       set number of numjobs
      --random            build packages in random order
      --rmsrc             remove local cached NoSource/NoPatch
      --url-alias "ALIAS" set an url alias
  -h  --help              show this message
END_OF_USAGE
  exit
end

begin
  io_methods = nil
  begin
    io_methods = IO.singleton_methods(false)
  rescue ArgumentError
    io_methods = IO.singleton_methods
  end

  if not io_methods.include?('read') then

    class IO
      def IO.read(path, length=nil, offset=nil)
        port = File.open(path)
        port.pos = offset if offset
        rv = nil
        begin
          rv = port.read(length)
        ensure
          port.close
        end
        rv
      end # def IO.read(path, length=nil, offset=nil)
    end # class IO

  end # if !IO.singleton_methods.include?('read') then
end

############ Variables ############
  $RPM_VER    = `LANG=C ; rpm --version`.split[2].split(/\./)[0].to_i
  $DEFAULT_ARCH = $ARCH

  $ARCHITECTURE       = $DEFAULT_ARCH
  $OS                 = `uname -s`.chop.downcase
  $MIRROR             = []
  $CONF_FILES         = ["./.OmoiKondara","~/.OmoiKondara","/etc/OmoiKondara.conf"]
  $TOPDIR             = ""
  $DEF_RPMOPT         = "-ba"
  $FORCE              = false
  $CVS                = false
  $VERBOSEOUT         = false
  $DEBUG_FLAG         = false
  $NONFREE            = false
  $NOSTRICT           = $CANNOTSTRICT
  $GROUPCHECK         = false
  $INSTALL            = false
  $FORCE_INSTALL      = false
  $SCRIPT             = false
  $MIRROR_FIRST       = false
  $SCANPACKAGES       = false
  $GLOBAL_NOCCACHE    = false
  $GLOBAL_CACHECC1    = false
  $CACHECC1_DISTCCDIR = "/nonexistent"
  $ARCH_DEP_PKGS_ONLY = false
  $IGNORE_REMOVE      = false
  $NOSWITCH_JAVA      = false
  $FTP_CMD            = ""
  $FORCE_FETCH        = false
  $CHECK_ONLY         = false
  $DISPLAY            = ":0.0"
  $LOG_FILE           = "OmoiKondara.log"
  $LOG_FILE_COMPRESS  = true
  $COMPRESS_CMD       = "bzip2 -f -9"
  $DEPEND_PACKAGE     = ""
  $MAIN_ONLY          = true
  $CHECKSUM_MODE      = "strict"
  $BUILD_ALTER        = false
  $BUILD_ORPHAN       = false
  $RANDOM_ORDER       = false
  $DEPGRAPH           = nil
  $RPMVERCMP        = "rpmvercmp"
  $SYSTEM_PROVIDES    = []
  class << $SYSTEM_PROVIDES
    def has_name?(name)
      rv = false
      each do |a|
        if a.name == name then
          rv = true
          break
        end
      end
      rv
    end
  end
  $ENABLE_DISTCC = false
  $DISTCC_HOSTS = []#'localhost']
  $DISTCC_VERBOSE = false
  $NUMJOBS = 1
  $WORKDIR = nil
  $RMSRC = false
  $STORE = nil
  $NODEPS = false
  $FULL_BUILD     = false

  GREEN           = "\e[1;32m"
  RED             = "\e[1;31m"
  YELLOW          = "\e[1;33m"
  BLUE            = "\e[1;34m"
  PINK            = "\e[1;35m"
  PURPLE          = "\e[0;35m"
  NOCOLOR         = "\e[m"
  SUCCESS         = "Success"
  FAILURE         = "Failure"
  SKIP            = "Skip"
  OBSOLETE        = "OBSOLETE"
  CHECKSUM        = "Checksum"
  NOTFOUND        = "Notfound"
  BUILDREQ        = "BuildReq"
  SIGINT          = "Interrupted"
  RETRY_FTPSEARCH = 10
  DOMAIN          = ".jp"

  GROUPS = [
    "Amusements/Games",
    "Amusements/Graphics",
    "Applications/Archiving",
    "Applications/Communications",
    "Applications/Databases",
    "Applications/Editors",
    "Applications/Emulators",
    "Applications/Engineering",
    "Applications/File",
    "Applications/Internet",
    "Applications/Multimedia",
    "Applications/Productivity",
    "Applications/Publishing",
    "Applications/System",
    "Applications/Text",
    "Development/Debuggers",
    "Development/Debug",
    "Development/Languages",
    "Development/Libraries",
    "Development/System",
    "Development/Tools",
    "Documentation",
    "System Environment/Base",
    "System Environment/Daemons",
    "System Environment/Kernel",
    "System Environment/Libraries",
    "System Environment/Shells",
    "User Interface/Desktops",
    "User Interface/X",
    "User Interface/X Hardware Support",
  ]

############ Main ############
ENV['PATH'] = "../tools:#{ENV['PATH']}"
options = [
  ["-A", "--arch",         GetoptLong::REQUIRED_ARGUMENT],
  ["-C", "--noccache",     GetoptLong::NO_ARGUMENT],
  ["-D", "--distcc",       GetoptLong::NO_ARGUMENT],
  ["-F", "--force-fetch",  GetoptLong::NO_ARGUMENT],
  ["-G", "--debug",        GetoptLong::NO_ARGUMENT],
  ["-J", "--noswitch-java",GetoptLong::NO_ARGUMENT],
  ["-L", "--alter",        GetoptLong::NO_ARGUMENT],
  ["-M", "--mirrorfirst",  GetoptLong::NO_ARGUMENT],
  ["-N", "--nostrict",     GetoptLong::NO_ARGUMENT],
  ["-O", "--orphan",       GetoptLong::NO_ARGUMENT],
  ["-R", "--ignore-remove",GetoptLong::NO_ARGUMENT],
  ["-S", "--scanpackages", GetoptLong::NO_ARGUMENT],
  ["-a", "--archdep",      GetoptLong::NO_ARGUMENT],
  ["-c", "--cvs",          GetoptLong::NO_ARGUMENT],
  ["-d", "--depend",       GetoptLong::REQUIRED_ARGUMENT],
  ["-f", "--force",        GetoptLong::NO_ARGUMENT],
  ["-g", "--checkgroup",   GetoptLong::NO_ARGUMENT],
  ["-i", "--install",      GetoptLong::NO_ARGUMENT],
  ["-m", "--main",         GetoptLong::NO_ARGUMENT],
  ["-n", "--nonfree",      GetoptLong::NO_ARGUMENT],
  ["-o", "--check-only",   GetoptLong::NO_ARGUMENT],
  ["-r", "--rpmopt",       GetoptLong::REQUIRED_ARGUMENT],
  ["-s", "--script",       GetoptLong::NO_ARGUMENT],
  ["-v", "--verbose",      GetoptLong::NO_ARGUMENT],
  ["-z", "--zoo",          GetoptLong::NO_ARGUMENT],
  ["-1", "--cachecc1",     GetoptLong::NO_ARGUMENT],
  ["--checksum",           GetoptLong::REQUIRED_ARGUMENT],
  ["--forceinstall",       GetoptLong::NO_ARGUMENT],
  ["--ftpcmd",             GetoptLong::REQUIRED_ARGUMENT],
  ["--fullbuild",          GetoptLong::NO_ARGUMENT],
  ["--nodeps",             GetoptLong::NO_ARGUMENT],
  ["--noworkdir",          GetoptLong::NO_ARGUMENT],
  ["--numjobs",            GetoptLong::REQUIRED_ARGUMENT],
  ["--random",             GetoptLong::NO_ARGUMENT],
  ["--rmsrc",              GetoptLong::NO_ARGUMENT],
  ["--url-alias",          GetoptLong::REQUIRED_ARGUMENT],
  ["-h", "--help",         GetoptLong::NO_ARGUMENT]
]

parse_conf

begin
  GetoptLong.new(*options).each do |on, ov|
    case on
    when "-a"
      $ARCH_DEP_PKGS_ONLY = true
    when "-A"
      $ARCHITECTURE = ov
    when "-c"
#      $CVS = true
      $CVS = $CVS    #nop
    when "-d"
      $DEPEND_PACKAGE = ov
    when "-f"
      $FORCE = true
    when "-g"
      $GROUPCHECK = true
    when "-i"
      $INSTALL = true
#    when "-I"
#      $FORCE_INSTALL = true
    when "-m"
#      $MAIN_ONLY = true
    when "-F"
      $FORCE_FETCH = true
    when "-o"
      $CHECK_ONLY = true
    when "-n"
      $NONFREE = true
      $MAIN_ONLY = false
    when "-N"
      $NOSTRICT = true unless $CANNOTSTRICT
    when "-r"
      $DEF_RPMOPT = ov if ov
    when "-R"
      $IGNORE_REMOVE = true
    when "-J"
      $NOSWITCH_JAVA = true
    when "-s"
      $SCRIPT = true
    when "-S"
      $SCANPACKAGES = true
    when "-v"
      $VERBOSEOUT = true
    when "-G"
      $DEBUG_FLAG = true
    when "-C"
      $GLOBAL_NOCCACHE = true
    when "-1"
      $GLOBAL_CACHECC1 = true
    when "-M"
      $MIRROR_FIRST = true
    when "-D"
      if File.executable?("/usr/bin/distcc") then
        $ENABLE_DISTCC = true
      end
    when "-O"
      $MAIN_ONLY = false
      $BUILD_ORPHAN = true
    when "-L"
      $MAIN_ONLY = false
      $BUILD_ALTER = true
    when "-z"
      $MAIN_ONLY = false
    when "--checksum"
      unless ['strict', 'workaround', 'maintainer'].include?(ov)
        raise GetoptLong::InvalidOption, 'You can use strict, workaround or maintainer only with --checksum option'
      end
      $CHECKSUM_MODE = ov
    when "--random"
      $RANDOM_ORDER = true
    when "--nodeps"
      $NODEPS = true
    when "--numjobs"
      $NUMJOBS = ov
    when "--ftpcmd"
      $FTP_CMD = ov
    when "--forceinstall"
      $FORCE_INSTALL = true
    when "--fullbuild"
      $FULL_BUILD = true
    when "--url-alias"
      pair = ov.split(' ')
      $URL_ALIAS[Regexp.compile(pair[0])] = pair[1]
    when "--noworkdir"
      $WORKDIR = nil
    when "--rmsrc"
      $RMSRC = true
    when "-h"
      show_usage
    end
  end
rescue GetoptLong::InvalidOption
  print $!.message, "\n"
  exit 1
rescue
  exit 1
end

