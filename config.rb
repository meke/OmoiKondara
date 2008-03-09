
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
      end
    end
    return
  end
end

def show_usage()
  print <<END_OF_USAGE
Usage: ../tools/OmoiKondara [options] [names]
  -a, --archdep           ignore noarch packages
  -A, --arch "ARCH"       specify architecture
  -c, --cvs               (ignored. remained for compatibility)
  -d, --depend "DEPENDS"  specify dependencies
  -f, --force             force build
  -F  --force-fetch       force fetch NoSource/NoPatch
  -o  --check-only        checksum compare(run "rpmbuild -bp")
  -g, --checkgroup        group check only
  -i, --install           force install after build (except kernel and usolame)
  -m, --main              main package only
  -n, --nonfree           build Nonfree package, too
  -N, --nostrict          proceed by old behavior
  -r, --rpmopt "RPMOPTS"  specify option through to rpm
  -R, --ignore-remove     do not uninstall packege if REMOVE.* exists
  -s, --script            script mode
  -S, --scanpackages      execute mph-scanpackage
  -v, --verbose           verbose mode
  -G, --debug             enable debug flag
  -C, --noccache          no ccache
  -1, --cachecc1          use cachecc1
  -M, --mirrorfirst       download from mirror first
  -D, --distcc            enable to use distcc
  -O, --orphan            build Orphan package, too
  -L, --alter             build Alter(alternative) package, too
  -z, --zoo               build Zoo package, too
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
  $SCRIPT             = false
  $MIRROR_FIRST       = false
  $SCANPACKAGES       = false
  $GLOBAL_NOCCACHE    = false
  $GLOBAL_CACHECC1    = false
  $CACHECC1_DISTCCDIR = "/nonexistent"
  $ARCH_DEP_PKGS_ONLY = false
  $IGNORE_REMOVE      = false
  $FTP_CMD            = ""
  $FORCE_FETCH        = false
  $CHECK_ONLY         = false
  $DISPLAY            = ":0.0"
  $LOG_FILE           = "OmoiKondara.log"
  $LOG_FILE_COMPRESS  = true
  $DEPEND_PACKAGE     = ""
  $MAIN_ONLY          = true
  $BUILD_ALTER        = false
  $BUILD_ORPHAN       = false
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
  ["-a", "--archdep",      GetoptLong::NO_ARGUMENT],
  ["-A", "--arch",         GetoptLong::REQUIRED_ARGUMENT],
  ["-c", "--cvs",          GetoptLong::NO_ARGUMENT],
  ["-d", "--depend",       GetoptLong::REQUIRED_ARGUMENT],
  ["-f", "--force",        GetoptLong::NO_ARGUMENT],
  ["-F", "--force-fetch",  GetoptLong::NO_ARGUMENT],
  ["-o", "--check-only",   GetoptLong::NO_ARGUMENT],
  ["-g", "--checkgroup",   GetoptLong::NO_ARGUMENT],
  ["-i", "--install",      GetoptLong::NO_ARGUMENT],
  ["-m", "--main",         GetoptLong::NO_ARGUMENT],
  ["-n", "--nonfree",      GetoptLong::NO_ARGUMENT],
  ["-N", "--nostrict",     GetoptLong::NO_ARGUMENT],
  ["-r", "--rpmopt",       GetoptLong::REQUIRED_ARGUMENT],
  ["-R", "--ignore-remove",GetoptLong::NO_ARGUMENT],
  ["-s", "--script",       GetoptLong::NO_ARGUMENT],
  ["-S", "--scanpackages", GetoptLong::NO_ARGUMENT],
  ["-v", "--verbose",      GetoptLong::NO_ARGUMENT],
  ["-G", "--debug",        GetoptLong::NO_ARGUMENT],
  ["-C", "--noccache",     GetoptLong::NO_ARGUMENT],
  ["-1", "--cachecc1",     GetoptLong::NO_ARGUMENT],
  ["-M", "--mirrorfirst",  GetoptLong::NO_ARGUMENT],
  ["-D", "--distcc",       GetoptLong::NO_ARGUMENT],
  ["-O", "--orphan",       GetoptLong::NO_ARGUMENT],
  ["-L", "--alter",        GetoptLong::NO_ARGUMENT],
  ["-z", "--zoo",          GetoptLong::NO_ARGUMENT],
  ["-h", "--help",         GetoptLong::NO_ARGUMENT]
]


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
    when "-h"
      show_usage
    end
  end
rescue
  exit 1
end

ENV['PATH'] = ENV['PATH'].split(':').select{|a| a !~ %r!/usr/bin/ccache!}.join(':')

parse_conf
