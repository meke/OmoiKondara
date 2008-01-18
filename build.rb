# -*- ruby-mode -*-
#
#

require 'dependency'
require 'expandmacro'
require 'check'
require 'getsource'
require 'backup'

# カレントディレクトリに rpmrc を生成する
#
# !!FIXME!!  現状では path== Dir.pwd の場合しか動作しないと思われる
#
def generate_rpmrc(path)
  if $DEBUG_FLAG then
    `grep -v macrofiles ../rpmrc.debug > rpmrc`
  else
    `grep -v macrofiles ../rpmrc > rpmrc`
  end
  macrofiles = `grep macrofiles ../rpmrc`.chop
  `echo #{macrofiles}#{path}/rpmmacros >> rpmrc`
  `echo %_topdir #{path} > rpmmacros`
  `echo %_arch #{$ARCHITECTURE} >> rpmmacros`
  `echo %_host_cpu #{$ARCHITECTURE} >> rpmmacros`
  `echo %_host_vender momonga >> rpmmacros`
  `echo %_host_os linux >> rpmmacros`
  `echo %_numjobs #{$NUMJOBS} >> rpmmacros`
  `echo %smp_mflags -j%{_numjobs} >> rpmmacros`
  `echo %_smp_mflags -j%{_numjobs} >> rpmmacros`
  if $ENABLE_DISTCC then #and $DISTCC_HOSTS.length > 1 then
    `echo %OmoiKondara_enable_distcc 1 >> rpmmacros`
  else
    `echo %OmoiKondara_enable_distcc 0 >> rpmmacros`
  end
  if $DEBUG_FLAG then
    `echo %OmoiKondara_enable_debug 1 >> rpmmacros`
    `echo '%__os_install_post    \\' >> rpmmacros`
    `echo '    /usr/lib/rpm/brp-compress \\' >> rpmmacros`
    `echo '    /usr/lib/rpm/modify-init.d \\' >> rpmmacros`
    `echo '%{nil}' >> rpmmacros`
  else
    `echo %OmoiKondara_enable_debug 0 >> rpmmacros`
  end
end

#  rpmbuild を実行する
#  buildme から呼ばれる
def do_rpmbuild(hTAG, log_file)
  result = MOMO_UNDEFINED

  pkg = hTAG['NAME']
  momo_debug_log("do_rpmbuild #{pkg}")

  Dir.chdir pkg

  STDOUT.flush
  install = false

  # 環境変数の設定
  if !$GLOBAL_NOCCACHE then
    if Dir.glob("#{pkg}/NO.CCACHE").length == 0 then
      if ENV['PATH'] !~ /ccache/ && `rpm -q ccache 2>/dev/null` =~ /^ccache/ then
        ENV['PATH'] = "/usr/libexec/ccache:#{ENV['PATH']}"
      end
    else
      ENV['PATH'] = ENV['PATH'].split(':').select{|a| a !~ %r!/usr/libexec/ccache!}.join(':')
    end
  end
  if $GLOBAL_CACHECC1 then
    if File.exist?("#{pkg}/NO.CACHECC1") or
        File.exist?("#{pkg}/NO.CCACHE") then
      unless ENV['LD_PRELOAD'].nil? then
        ENV['LD_PRELOAD'] = ENV['LD_PRELOAD'].split(/ /).select{|a| a !~ %r!^/usr/lib/cachecc1\.so$!}.join(' ')
      end
    else
      if ENV['LD_PRELOAD'] !~ /cachecc1\.so/ && `rpm -q cachecc1 2>/dev/null` =~ /^cachecc1/ then
        ENV['LD_PRELOAD'] = "/usr/lib/cachecc1.so #{ENV['LD_PRELOAD']}"
      end
      if !ENV['CACHECC1_DIR'] then
        ENV['CACHECC1_DIR'] = "#{ENV['HOME']}/.cachecc1"
      end
    end
  end
  if $ENABLE_DISTCC then #and $DISTCC_HOSTS.length > 1 then
    ENV["DISTCC_VERBOSE"] = "1" if $DISTCC_VERBOSE
    ENV["DISTCC_HOSTS"] = $DISTCC_HOSTS.join(' ')
    ENV["CACHECC1_DISTCCDIR"] = $CACHECC1_DISTCCDIR
  end

  # カレントディレクトリに rpmrc を生成
  generate_rpmrc(Dir.pwd)

  # rpmbuild のオプション
  rpmopt = $DEF_RPMOPT
  if is_srpm_only(pkg) then
    rpmopt = "-bs"
  end
  if $CHECK_ONLY then # -o option
    rpmopt = "-bp"
  end
  rpmopt += " --target #{$ARCHITECTURE}"
  
  if !$IGNORE_REMOVE && !$CHECK_ONLY && File.exist?("REMOVE.PLEASE") && /\-ba|\-bb/ =~ rpmopt then
    # .spec をパースしてすべてのサブパッケージを消すべき。
    # すべての .spec の依存関係がただしければ、依存するものも
    # 全消去するべき。
    RPM.readrc("./rpmrc")
    RPM::Spec.open(pkg+".spec").packages.each do |subpkg|
      exec_command("sudo rpm -e --nodeps #{subpkg.name}", log_file)
    end
    install = true
  end
  Dir.glob("REMOVEME.*").each do |r|
    rp = r.split(/\./)[1]
    if `rpm -q #{rp}` =~ /^#{rp}/ then
      `sudo rpm -e --nodeps #{rp}`
      install = true
    end
  end if !$IGNORE_REMOVE && rpmopt =~ /\-ba|\-bb/

  install = true if $INSTALL && /^(kernel|usolame)/ !~ pkg
  
  if (File.exist? "DISPLAY.PLEASE") && !(ENV.has_key? "DISPLAY")
    ENV["DISPLAY"]=$DISPLAY
  end

  lang = Dir.glob("LANG*")
  lang = lang.size.zero? ? "" : "env #{lang[0]} "
  need_timeout = File.exist?("TIMEOUT.PLEASE")

  # rpmbuild の実行
  rpmerr = nil
  cmd = "rpmbuild --rcfile rpmrc #{rpmopt} #{pkg}.spec"
  if File.exist?("SU.PLEASE") then
    rpmerr = exec_command("#{lang}sudo #{cmd}", log_file, need_timeout)
  else
    rpmerr = exec_command("#{lang} #{cmd}", log_file, need_timeout)
  end

  if 0 == rpmerr then
    result = MOMO_SUCCESS
  else
    result = MOMO_FAILURE
  end

  # 後始末
  ENV.delete("DISPLAY") if File.exist?("DISPLAY.PLEASE")
  if rpmerr == 0 then
    clean_up(hTAG, install, rpmopt, log_file) if rpmopt =~ /\-ba|\-bb|\-bs|\-bp/
  else
    if $WORKDIR then
      workdir = $WORKDIR + "/" + hTAG["NAME"] + "-" +
        hTAG["VERSION"] + "-" + hTAG["RELEASE"]
      if $DEBUG_FLAG then
        $stderr.puts "INFO: workdir is #{workdir}"
      end
      #        File.unlink "BUILD"
      #        if $DEBUG_FLAG then
      #          $stderr.puts "MSG: File.unlink BUILD"
      #        end
      exec_command("[ -L BUILD ] && rm BUILD", log_file)
      exec_command("mv #{workdir} BUILD", log_file)
      if $DEBUG_FLAG then
        $stderr.puts "MSG: mv #{workdir} BUILD"
      end
    end
  end

ensure
  Dir.chdir ".."
  momo_debug_log("do_rpmbuild returns #{result}")
  return result
end

# rpmbuild 成功時の処理
# do_rpmbuild() から呼ばれる 
#
def clean_up(hTAG, install, rpmopt, log_file)
  momo_debug_log("clean_up #{hTAG['NAME']}")

  prepare_outputdirs(hTAG, log_file)
  backup_rpms(hTAG, install, rpmopt, log_file)
  pkg = hTAG['NAME']
  exec_command("rpmbuild --rmsource --rcfile rpmrc #{pkg}.spec", log_file)
  File.delete "rpmrc"
  File.delete "rpmmacros"

  # $DEBUG_FLAG が non nilだとBUILDを消さないで残す
  # $CHECK_ONLY が non nilの場合もBUILDを消さないで残す (-o option)
  # $DEF_RPMOPT に -bp が含まれる場合もBUILDを消さないで残す(-r -bp の場合)
  if $DEBUG_FLAG or $CHECK_ONLY or /\-bp/ =~ $DEF_RPMOPT then
    if File.exist?("SU.PLEASE") then
      exec_command("sudo rm -rf SOURCES RPMS SRPMS", log_file)
    else
      exec_command("rm -rf SOURCES RPMS SRPMS", log_file)
    end
  else
    if File.exist?("SU.PLEASE") then
      exec_command("sudo rm -rf SOURCES RPMS SRPMS BUILD ", log_file)
    else
      exec_command("rm -rf SOURCES RPMS SRPMS BUILD ", log_file)
    end
  end

  if $WORKDIR then
    workdir = $WORKDIR + "/" + hTAG["NAME"] + "-" +
      hTAG["VERSION"] + "-" + hTAG["RELEASE"]
    if File.exist?("SU.PLEASE") then
      exec_command("sudo rm -rf ./BUILD", log_file)
      exec_command("sudo rm -rf #{workdir}", log_file)
    else
      exec_command("rm -rf ./BUILD", log_file)
      exec_command("rm -rf #{workdir}", log_file)
    end
    if $DEBUG_FLAG then
      $stderr.puts "MSG: exec_command rm -rf ./BUILD"
      $stderr.puts "MSG: exec_command rm -rf #{workdir}"
    end
  end
end


def get_specdata(pkg)
  if $NOSTRICT then
    s = IO.read("#{pkg}/#{pkg}.spec")
    hTAG = strip_spec s
  else
    hTAG = make_hTAG(pkg)
  end
  momo_assert{ "#{pkg}" == "#{hTAG['NAME']}" }  

  return hTAG
end

def is_srpm_only(pkg)
  # !!FIXME!!
  # 2007/2/11時点での仕様では，SRPM.ONLY は無視される模様

  #    if Dir.glob("#{pkg}/SRPM.ONLY").length != 0 then
  return false
end

def is_build_required(hTAG)
  pkg = hTAG['NAME']
  if test(?e, "#{pkg}/#{$NOTFILE}")
    return MOMO_SKIP
  end
  if File.exist?("#{pkg}/SKIP") or
      File.exist?("#{pkg}/.SKIP") then
    return MOMO_SKIP
  end
  if Dir.glob("#{pkg}/TO.*").length != 0 && $MAIN_ONLY then
    return MOMO_SKIP
  end
  if !$BUILD_ALTER && File.exist?("#{pkg}/TO.Alter") then
    return MOMO_SKIP
  end
  if !$BUILD_ORPHAN && File.exist?("#{pkg}/TO.Orphan") then
    return MOMO_SKIP
  end
  if !$NONFREE && File.exist?("#{pkg}/TO.Nonfree") then
    return MOMO_SKIP
  end
  if File.exist?("#{pkg}/OBSOLETE") then
    return MOMO_OBSOLETE
  end  

  check_group(hTAG)
  ## !!FIXME!!   $GROUPCHECKはつねにfalse??
  if $GROUPCHECK then
    return MOMO_SKIP
  end
  if ($ARCH_DEP_PKGS_ONLY and
        (hTAG['BUILDARCHITECTURES'] == "noarch" or
           hTAG['BUILDARCH'] == "noarch")) then
    return MOMO_SKIP
  end

  # *.rpm と *.spec のタイムスタンプを比較
  topdir = get_topdir(hTAG['NAME'])
  if Dir.glob("#{topdir}/SRPMS/#{pkg}-*.rpm").length != 0 then
    match_srpm = ""
    Dir.glob("#{topdir}/SRPMS/#{pkg}-*.rpm").each do |srpms|
      pn = srpms.split("/")[-1].split("-")[0..-3].join("-")
      if pn == pkg then
        match_srpm = srpms
        break
      end
    end
    if !$FORCE && match_srpm != "" then
      if File.mtime("#{pkg}/#{pkg}.spec") <= File.mtime(match_srpm)
        return MOMO_SKIP
      end
    end
  end
  return MOMO_SUCCESS
end

def prepare_builddirs(hTAG, log_file)
  momo_debug_log("prepare_builddirs #{hTAG['NAME']}")

  if $WORKDIR then
    if File.exist?(hTAG["NAME"] + "/BUILD") then
      exec_command("rm -rf #{hTAG['NAME']}/BUILD", log_file)
      if $DEBUG_FLAG then
        $stderr.puts "\n"
        $stderr.puts "MSG: exec_command rm -rf #{hTAG['NAME']}/BUILD"
      end
    end
    
    if FileTest.symlink?(hTAG["NAME"] + "/BUILD") then
      File.unlink(hTAG["NAME"] + "/BUILD")
      if $DEBUG_FLAG then
        $stderr.puts "MSG: File.unlink #{hTAG['NAME']}/BUILD"
      end
    end

    if $FORCE_FETCH then
      if File.exist?($hTAG["NAME"] + "/SOURCES") then
        exec_command "rm -rf #{$hTAG['NAME']}/SOURCES"
        if $DEBUG_FLAG then
          $stderr.puts "\n"
          $stderr.puts "MSG: exec_command rm -rf #{$hTAG['NAME']}/SOURCES"
        end
      end

      if FileTest.symlink?($hTAG["NAME"] + "/SOURCES") then
        File.unlink($hTAG["NAME"] + "/SOURCES")
        if $DEBUG_FLAG then
          $stderr.puts "MSG: File.unlink #{$hTAG['NAME']}/SOURCES"
        end
      end
    end

    workdir = $WORKDIR + "/" + hTAG["NAME"] + "-" +
      hTAG["VERSION"] + "-" + hTAG["RELEASE"]
    if $DEBUG_FLAG then
      $stderr.puts "INFO: workdir is #{workdir}"
    end
    
    if not File.exist?(workdir) then
      Dir.mkdir(workdir)
      if $DEBUG_FLAG then
        $stderr.puts "MSG: mkdir #{workdir}"
      end
    end
    
    File.symlink(workdir, hTAG["NAME"] + "/BUILD")
    if $DEBUG_FLAG then
      $stderr.puts "MSG: symlink #{workdir} #{hTAG["NAME"]}/BUILD"
    end
  else
    prepare_dirs(hTAG, ["BUILD"])
  end

  prepare_dirs(hTAG,["SOURCES", "RPMS/#{$ARCHITECTURE}", "RPMS/noarch", "SRPMS"])
end

def prepare_buildreqs(hTAG, name_stack, blacklist, log_file)
  momo_debug_log("prepare_buildreqs #{hTAG['NAME']}")
  rc = MOMO_SUCCESS
  if $NOSTRICT then
    rc = chk_requires(hTAG, name_stack, blacklist, log_file)
  else
    rc = chk_requires_strict(hTAG, name_stack, blacklist, log_file)
  end

  momo_debug_log("prepare_buildreqs returns #{rc}");
  
  case rc
  when MOMO_LOOP, MOMO_FAILURE
    throw :exit_buildme, rc
  end
end

def prepare_sources(hTAG, log_file)
  momo_debug_log("prepare_sources #{hTAG['NAME']}")
  if !get_no(hTAG, "SOURCE", log_file) then
    throw :exit_buildme, MOMO_FAILURE
  end
  if !get_no(hTAG, "PATCH", log_file) then
    throw :exit_buildme, MOMO_FAILURE
  end
  cp_to_tree(hTAG, log_file)
end

def prepare_outputdirs(hTAG, log_file)
  momo_debug_log("prepare_outputdirs #{hTAG['NAME']}")

  topdir = get_topdir(hTAG['NAME'], "..")
  ["SOURCES", "SRPMS", "#{$ARCHITECTURE}", "noarch"].each do |subdir|
    if !File.directory?("#{topdir}/#{subdir}") then
      exec_command("mkdir -p #{topdir}/#{subdir}", log_file)
    end
  end
end

#
# $NAME_STACK に pkg を push
# pkg を ビルドする
# $NAME_STACK から pkg を pop
#
def buildme(pkg, name_stack, blacklist)
  momo_debug_log("buildme pkg:#{pkg}")

  log_file = nil
  if !$VERBOSEOUT then
    print "\r#{pkg} "
    print "-" * [51 - pkg.length, 1].max, "> "
    STDOUT.flush
  end
  
  ret = catch(:exit_buildme) do
    if !File.exist?("#{pkg}/#{pkg}.spec") then
      throw :exit_buildme, MOMO_NO_SUCH_PACKAGE
    end
    
    # blacklist に登録されているpkgは 容赦なく MOMO_FAILURE
    if blacklist.include?(pkg) then
      throw :exit_buildme, MOMO_FAILURE
    end

    # ループの検出
    if name_stack.include?(pkg) then
      throw :exit_buildme, MOMO_LOOP
    end
    name_stack.push(pkg)

    log_file= "#{Dir.pwd}/#{pkg}/#{$LOG_FILE}"

    # specのタグの情報を ハッシュ hTAG に格納
    hTAG = get_specdata(pkg)
    
    ret = is_build_required(hTAG)
    if MOMO_SUCCESS != ret then
      throw :exit_buildme, ret
    end

    # ビルド開始
    backup_logfile(log_file)

    srpm_only = is_srpm_only(pkg)
    # buildreq を解析して，必要なパッケージを build & install
    if !srpm_only then
      prepare_buildreqs(hTAG, name_stack, blacklist, log_file)
    end

    # ビルド用ディレクトリを作り，ソースコードをダウンロード or コピー
    prepare_builddirs(hTAG, log_file)    
    prepare_sources(hTAG, log_file)    
    Dir.chdir "#{pkg}"
    prepare_outputdirs(hTAG, log_file)
    backup_nosources(hTAG, srpm_only, log_file)
    Dir.chdir '..'
    
    # rpmbuild を実行
    throw :exit_buildme, do_rpmbuild(hTAG, log_file)    
  end
  
ensure
  if !$VERBOSEOUT then
    case ret
    when MOMO_NO_SUCH_PACKAGE
    when nil
    when MOMO_SUCCESS
      print GREEN unless $SCRIPT
      print "#{SUCCESS}"
      print NOCOLOR unless $SCRIPT
      print "\n"
    when MOMO_SKIP
      print YELLOW unless $SCRIPT
      print "#{SKIP}"
      print NOCOLOR unless $SCRIPT
      print "\n"
    when MOMO_OBSOLETE
      print BLUE unless $SCRIPT
      print "#{OBSOLETE}"
      print NOCOLOR unless $SCRIPT
      print "\n"
    else
      print RED unless $SCRIPT
      print "#{FAILURE}"
      print NOCOLOR unless $SCRIPT
      print "\n"
    end
  end

  if log_file then
    case ret
    when MOMO_SUCCESS
      open("#{log_file}", "a") do |fLOG|
        fLOG.puts "\n#{SUCCESS} : #{pkg}"
      end
    when MOMO_SKIP
    when MOMO_FAILURE      
    else
      open("#{log_file}", "a") do |fLOG|
        fLOG.puts "\n#{FAILURE} : #{pkg}"
      end
    end
  end

  ## ビルドに失敗したパッケージがあれば blacklist に登録
  if ret == MOMO_FAILURE then
    blacklist.push(pkg)
  end
  
  ## !!FIXME!!
  ## ビルドに成功したパッケージがあれば
  ##  blacklistから関係しそうなパッケージを削除

  if ret == MOMO_LOOP then
    STDERR.puts "BuildRequire and/or BuildPreReq is looped:"
    name_stack.each{|a| STDERR.puts "  #{a}"}
  else
    name_stack.pop
  end

  return ret
end

def recursive_build(path, name_stack, blacklist)
  pwd = Dir.pwd
  Dir.chdir path
  `ls ./`.each_line do |pn|
    pn.chop!
    if File.directory?(pn) && pn != "BUILD" then
      if pn != "CVS" && pn != "." && pn != ".." &&
          File.exist?("#{pn}/#{pn}.spec") then
        recursive_build(pn, name_stack, blacklist)
      end
    else
      if pn =~ /^.+\.spec$/ &&
          ( File.exist?("CVS/Repository") || File.exist?(".svn/entries") ) then
        pkg = Dir.pwd.split("/")[-1]
        Dir.chdir ".."
        buildme(pkg, name_stack, blacklist)
        if $CHECK_ONLY then
          next
        end
        Dir.chdir pkg
      end
    end
  end

ensure
  Dir.chdir pwd
end



