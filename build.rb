# -*- ruby-mode -*-
#
#

require 'dependency'
require 'expandmacro'
require 'check'
require 'getsource'
require 'backup'

#
#  rpmbuild を実行する
# 
def do_rpmbuild(hTAG)
  pkg = hTAG['NAME']
  STDOUT.flush
  Dir.chdir pkg
  install = false
  path = Dir.pwd
  if $ENABLE_DISTCC then #and $DISTCC_HOSTS.length > 1 then
    ENV["DISTCC_VERBOSE"] = "1" if $DISTCC_VERBOSE
    ENV["DISTCC_HOSTS"] = $DISTCC_HOSTS.join(' ')
    ENV["CACHECC1_DISTCCDIR"] = $CACHECC1_DISTCCDIR
  end
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
  if !$IGNORE_REMOVE && File.exist?("REMOVE.PLEASE") && /\-ba|\-bb/ =~ $RPMOPT then
    # .spec をパースしてすべてのサブパッケージを消すべき。
    # すべての .spec の依存関係がただしければ、依存するものも
    # 全消去するべき。
    RPM.readrc("./rpmrc")
    RPM::Spec.open(pkg+".spec").packages.each do |subpkg|
      exec_command "sudo rpm -e --nodeps #{subpkg.name}"
    end
    install = true
  end
  Dir.glob("REMOVEME.*").each do |r|
    rp = r.split(/\./)[1]
    if `rpm -q #{rp}` =~ /^#{rp}/ then
      `sudo rpm -e --nodeps #{rp}`
      install = true
    end
  end if !$IGNORE_REMOVE && $RPMOPT =~ /\-ba|\-bb/
  install = true if $INSTALL && /^(kernel|usolame)/ !~ pkg
  if (File.exist? "DISPLAY.PLEASE") && !(ENV.has_key? "DISPLAY")
    ENV["DISPLAY"]=$DISPLAY
  end
  rpmerr = nil
  lang = Dir.glob("LANG*")
  lang = lang.size.zero? ? "" : "env #{lang[0]} "
  need_timeout = File.exist?("TIMEOUT.PLEASE")
  if File.exist?("SU.PLEASE") then
    rpmerr = exec_command "#{lang}sudo rpmbuild --rcfile rpmrc #{$RPMOPT} #{pkg}.spec", need_timeout
  else
    rpmerr = exec_command "#{lang}rpmbuild --rcfile rpmrc #{$RPMOPT} #{pkg}.spec", need_timeout
  end
  ENV.delete("DISPLAY") if File.exist?("DISPLAY.PLEASE")
  if rpmerr == 0 then
    clean_up(hTAG,install) if $RPMOPT =~ /\-ba|\-bb|\-bs/
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
      exec_command "[ -L BUILD ] && rm BUILD"
      exec_command "mv #{workdir} BUILD"
      if $DEBUG_FLAG then
        $stderr.puts "MSG: mv #{workdir} BUILD"
      end
    end
  end
  Dir.chdir ".."
  return rpmerr
end


#
# $NAME_STACK に pkg を push
# pkg を ビルドする
# $NAME_STACK から pkg を pop
#
def buildme(pkg, name_stack)
  ret = nil
  if name_stack.include?(pkg) then
    ret = MOMO_LOOP
    return
  end
  name_stack.push(pkg)
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
  #    if Dir.glob("#{pkg}/SRPM.ONLY").length != 0 then
  if false
    $SRPM_ONLY = true
    $RPMOPT = "-bs"
  else
    $SRPM_ONLY = false
    $RPMOPT = $DEF_RPMOPT
  end
  $RPMOPT += " --target #{$ARCHITECTURE}"
  
  if !$VERBOSEOUT then
    print "\r#{pkg} "
    print "-" * [51 - pkg.length, 1].max, "> "
    STDOUT.flush
  end

  ret = catch(:exit_buildme) do
    if test(?e, "#{pkg}/#{$NOTFILE}")
      throw :exit_buildme, MOMO_SKIP
    end
    if File.exist?("#{pkg}/SKIP") or
        File.exist?("#{pkg}/.SKIP") then
      throw :exit_buildme, MOMO_SKIP
    end
    if File.exist?("#{pkg}/OBSOLETE") then
      throw :exit_buildme, MOMO_OBSOLETE
    end
    if Dir.glob("#{pkg}/TO.*").length != 0 && $MAIN_ONLY then
      throw :exit_buildme, MOMO_SKIP
    end
    if !$BUILD_ALTER && File.exist?("#{pkg}/TO.Alter") then
      throw :exit_buildme, MOMO_SKIP
    end
    if !$BUILD_ORPHAN && File.exist?("#{pkg}/TO.Orphan") then
      throw :exit_buildme, MOMO_SKIP
    end
    if !$NONFREE && File.exist?("#{pkg}/TO.Nonfree") then
      throw :exit_buildme, MOMO_SKIP
    end
    if File.directory?(pkg) then
      if File.exist?("#{pkg}/#{pkg}.spec") then
        backup_logfile(pkg)
        
        if $NOSTRICT then
          s = IO.read("#{pkg}/#{pkg}.spec")
          hTAG = strip_spec s
        else
          hTAG = make_hTAG(pkg)
        end

        momo_assert{ "#{pkg}" == "#{hTAG['NAME']}" }

        check_group(hTAG)
        if $GROUPCHECK then
          throw :exit_buildme, MOMO_SKIP
        end
        if ($ARCH_DEP_PKGS_ONLY and
              (hTAG['BUILDARCHITECTURES'] == "noarch" or
                 hTAG['BUILDARCH'] == "noarch")) then
          throw :exit_buildme, MOMO_SKIP
        end
        
        $LOG_PATH = "#{Dir.pwd}/#{hTAG['NAME']}"
        
        if !$SRPM_ONLY then
          rc = 0
          if $NOSTRICT then
            rc = chk_requires(hTAG, name_stack)
          else
            rc = chk_requires_strict(hTAG, name_stack)
          end
          if rc == MOMO_LOOP then
            throw :exit_buildme, MOMO_LOOP
          end
        end
        
        topdir = get_topdir(hTAG)
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
              throw :exit_buildme, MOMO_SKIP
            end
          end
        end
        
        if $WORKDIR then
          if File.exist?(hTAG["NAME"] + "/BUILD") then
            exec_command "rm -rf #{hTAG['NAME']}/BUILD"
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
        if !get_no(hTAG, "SOURCE") then
          throw :exit_buildme, MOMO_FAILURE
        end
        if !get_no(hTAG, "PATCH") then
          throw :exit_buildme, MOMO_FAILURE
        end
        cp_to_tree(hTAG)
        Dir.chdir "#{hTAG['NAME']}"
        prepare_outputdirs
        backup_nosources(hTAG)
        Dir.chdir '..'
        throw :exit_buildme, do_rpmbuild(hTAG)
      else
        throw :exit_buildme, MOMO_SKIP
      end
    end
  end
ensure
  if !$VERBOSEOUT then
    case ret
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
  case ret
  when nil
  when MOMO_SUCCESS
    open("#{$LOG_PATH}/#{$LOG_FILE}", "a") do |fLOG|
      fLOG.puts "\n#{SUCCESS} : #{pkg}"
    end
  when MOMO_SKIP
  when MOMO_FAILURE
  else
    open("#{$LOG_PATH}/#{$LOG_FILE}", "a") do |fLOG|
      fLOG.puts "\n#{FAILURE} : #{pkg}"
    end
  end
  if ret == MOMO_LOOP then
    STDERR.puts "BuildRequire and/or BuildPreReq is looped:"
    name_stack.each{|a| STDERR.puts "  #{a}"}
  end
  name_stack.pop
  ret
end

def recursive_build(path, name_stack)
  pwd = Dir.pwd
  Dir.chdir path
  for pn in `ls ./`
    pn.chop!
    if File.directory?(pn) && pn != "BUILD" then
      if pn != "CVS" && pn != "." && pn != ".." &&
          File.exist?("#{pn}/#{pn}.spec") then
        recursive_build(pn, name_stack)
      end
    else
      if pn =~ /^.+\.spec$/ &&
          ( File.exist?("CVS/Repository") || File.exist?(".svn/entries") ) then
        pkg = Dir.pwd.split("/")[-1]
        Dir.chdir ".."
        buildme(pkg, name_stack)
        Dir.chdir pkg
      end
    end
  end
  Dir.chdir pwd
end



def clean_up(hTAG, install)
  pkg=hTAG['NAME']
  prepare_outputdirs
  backup_rpms(install, pkg)
  exec_command "rpmbuild --rmsource --rcfile rpmrc #{pkg}.spec"
  File.delete "rpmrc"
  File.delete "rpmmacros"

  # DEBUG_FLAG が non nilだとBUILDを消さないで残す
  if $DEBUG_FLAG then
    if File.exist?("SU.PLEASE") then
      exec_command "sudo rm -rf SOURCES RPMS SRPMS"
    else
      exec_command "rm -rf SOURCES RPMS SRPMS"
    end
  else
    if File.exist?("SU.PLEASE") then
      exec_command "sudo rm -rf SOURCES BUILD RPMS SRPMS"
    else
      exec_command "rm -rf SOURCES BUILD RPMS SRPMS"
    end
  end

  if $WORKDIR then
    workdir = $WORKDIR + "/" + hTAG["NAME"] + "-" +
      hTAG["VERSION"] + "-" + hTAG["RELEASE"]
    if File.exist?("SU.PLEASE") then
      exec_command "sudo rm -rf ./BUILD"
      exec_command "sudo rm -rf #{workdir}"
    else
      exec_command "rm -rf ./BUILD"
      exec_command "rm -rf #{workdir}"
    end
    if $DEBUG_FLAG then
      $stderr.puts "MSG: exec_command rm -rf ./BUILD"
      $stderr.puts "MSG: exec_command rm -rf #{workdir}"
    end
  end
end
