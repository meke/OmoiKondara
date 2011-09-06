# -*- coding: utf-8 -*-

# BuildReq: に指定されていても、無視するパッケージ
$IGNORE_BUILDREQ_PKGS = ["rpmlib(VersionedDependencies)"]

# prov をprovideしている*.rpmを探す
#
# TODO 現実装は暫定的なものであり、
#      処理が遅く、対応する*.rpm を発見できない場合がある。
#
def search_rpm_files(prov)
  # 1) provをpkg名とみなし、ファイル名を推測
  topdir = get_topdir(prov)
  if $STORE then
    files = Dir.glob("#{topdir}*/#{$STORE}/#{prov}-*.rpm") 
  else
    files = Dir.glob("#{topdir}*/{#{$ARCHITECTURE},noarch}/#{prov}-*.rpm") 
  end
  files.delete_if {|f| prov!=File.basename(f).split("-")[0..-3].join("-") }
 
  if files.empty? then
    # 2) #{prov} を provide してそうなファイルの中から
    #     実際に provide しているものを探す
    
    topdir = File.expand_path $TOPDIR

    # #{prov}を実際にprovideしてそうなファイル名のパターンを生成
    pattern = "#{prov}"
    pattern.gsub!(/^pkgconfig\((.+)\)$/, '\1')
    pattern.gsub!(/\.so.*$/,'')
    pattern.gsub!(/^lib/,'')
    pattern.gsub!(/-[0-9.-]+$/,'')
    pattern.gsub!(/[0-9]+$/,'')
    # perl(hoge::fuga) =>  perl-hoge-fuga
    if pattern =~ /^perl\(.*\)$/ then
      pattern.gsub!(/\(/,'-')
      pattern.gsub!(/\)/,'-')
      pattern.gsub!(/::/,'-')

    # rubygem(hoge) => rubygem-hoge
    elsif pattern =~ /^rubygem\(.*\)$/ then
      pattern.gsub!(/\(/,'-')
      pattern.gsub!(/\)/,'')
    end
    pattern.downcase!

    find_result = if $STORE
                    `find #{topdir}*/#{$STORE} -iname "*#{pattern}*.rpm"`
                  else
                    `find #{topdir}*/{#{$ARCHITECTURE},noarch} -iname "*#{pattern}*.rpm"`
                  end
    find_result.each_line {|f|
      f.chomp!
      `rpm -qp --provides #{f}`.each_line {|p|
        if prov==p.split(' ')[0] then
          files.push(f)
          break
        end
      }
    }
  end
  
  if files.empty? then
    momo_debug_log("warning: search_rpm_files(#{prov}) founds no file")
  elsif files.size > 1 then
    momo_debug_log("warning: search_rpm_files(#{prov}) founds #{files.size} files; #{files.join(' ')} ")
  else 
    momo_debug_log("search_rpm_files(#{prov}) returns #{files.join(' ')}")
  end
  return files
end

# パッケージ pkg をinstallする
# - 依存関係が解決できない場合は 再帰的にbuild_and_installを呼び出す
# - installに成功した場合は、 $SYSTEM_PROVIDES を更新する
#
#
# TODO   ../tools/update-yum && sudo yum install #{pkg}  に差し替える？
#
#       当実装には以下の問題がある
#        -   provides:で提供された仮想package(?)等を解決できない
#        -   バージョンの確認がない
#

def install_pkg(pkg, name_stack, blacklist, log_file, retrycounter=10)
  result = MOMO_FAILURE
  momo_debug_log("install_pkg(#{pkg})")

  files = search_rpm_files(pkg)
  if files.empty? then
    log(log_file, "there is no rpm package providing #{pkg}")
    puts "there is no rpm package providing #{pkg}" if $VERBOSEOUT 
    return
  end

  # filesに登録されているpackage達をinstallする
  # installに失敗した場合は、最大 retrycounter回試行する
  while retrycounter > 0 do
    retrycounter = retrycounter - 1 

    files.uniq!

    # 依存関係を確認
    # 不足packageを missing に追加
    cmd="env LANG=C rpm -U --test #{files.join(' ')}"
    missing = []
    found = 0
    ret = `#{cmd} 2>&1`.split("\n").each do |line|
      if / is already installed/ =~ line then
        found = found + 1
      elsif / is needed by \(installed\) / =~ line  then
        missing.push( line.split(' ')[-1].split('-')[0..-3].join('-') )
      elsif / is needed by / =~ line then
        missing.push( line.split(' ')[0] )
      end
    end
    
    # すべてinstallずみの場合 skip
    if files.size == found then
      result = MOMO_SKIP
      return
    end

    # 依存関係が解決できた場合は install
    if missing.empty? then
      cmd="env LANG=C sudo rpm -Uvh --force #{files.join(' ')}"
      ret = exec_command("#{cmd}", log_file)

      # 成功時
      break if 0 == ret

      # 失敗時
      return

    else
      # 依存関係を解決
      missing.each do |p|
        f = search_rpm_files(p)

        if f.empty? then
          rc = build_and_install(p, "-Uvh", name_stack, blacklist, log_file)
          case rc
            when MOMO_LOOP, MOMO_FAILURE
            log(log_file, "failed to rebuild #{p}")
            puts "failed to rebuild #{p}" if $VERBOSEOUT
            return rc
            when MOMO_NO_SUCH_PACKAGE
            log(log_file, "could not find the package which provides #{p}")
            puts "could not find the package which provides #{p}" if $VERBOSEOUT
            return rc
          end

          # 依存関係を一つ解決したので、再度依存関係の確認処理に戻る
          break
        else
          # TODO   以下未実装
          # f.each do |sub|
          #  if (sub のバージョンが古ければ) then
          #       build_and_install(sub) 
          #  else
          #       files += sub
          #  end
          # end 

          # 依存関係を一つ解決したので、再度依存関係の確認処理に戻る
          files += f
          break
        end
      end
    end

  end 

  if retrycounter == 0 then
    cmd="env LANG=C rpm -U --test #{files.join(' ')}"
    ret=`#{cmd} 2>&1`
    open("#{log_file}", "a") { |f|
      f.puts "failed to solve dependencies, check the following messages for more information"
      f.puts ""
      f.puts "#{cmd}"
      f.puts "#{ret}"
      f.puts ""
    }
    return 
  end

  if not $CANNOTSTRICT then
    files.each do |a|
      begin
        rpmpkg = RPM::Package.open(a)
        rpmpkg.provides.each do |prov|
          if not $SYSTEM_PROVIDES.has_name?(prov.name) then
            $SYSTEM_PROVIDES.push(prov)
          end
        end
      ensure
        rpmpkg = nil
        GC.start
      end
    end
  end

  result = MOMO_SUCCESS
  return 

ensure
  case result
  when MOMO_SUCCESS, MOMO_SKIP
    result = MOMO_SUCCESS
  else
    result = MOMO_FAILURE
    momo_debug_log("install_pkg(#{pkg}) failed")
  end
  return result
end

=begin
--- chk_requires
TAG BuildPreReq, BuildRequires 行に記述されているパッ
ケージがあればそのパッケージがインストールされている
かどうか判断し、必要ならばインストールする。
rpm -ivh する関係上、sudo が password 無しで実行可能
である事。
=end
def chk_requires(hTAG, name_stack, blacklist, log_file)
  momo_debug_log("chk_requires #{hTAG['NAME']}")

  req = Array.new
  if hTAG.key?("BUILDPREREQ") then
    req = hTAG["BUILDPREREQ"].split(/[\s,]/)
  end
  if hTAG.key?("BUILDREQUIRES") then
    hTAG["BUILDREQUIRES"].split(/[\s,]/).each {|r| req.push r}
  end

  return MOMO_SUCCESS if req.empty?

  req.delete ""
  while r = req.shift do
    # 直接ファイル名が指定されている
    # パッケージ名を指定すべし
    next  if r =~ /\//

    # インストール済の場合 ir = <epoch>:<ver>-<rel>
    ir = `rpm -q --queryformat '%{EPOCH}:%{VERSION}-%{RELEASE}' "#{r}" 2>/dev/null`.split(':')
    r = r.split(/\-/)[0..-2].join("-") if r =~ /\-devel/

    if ir.length != 2 then
      rc = build_and_install(r, "-Uvh", name_stack, blacklist, log_file) 
      print_status(hTAG['NAME']) if !$VERBOSEOUT 
      case rc
      when MOMO_LOOP, MOMO_FAILURE
        return rc
      end
      # バージョン情報をスキップする
      if req[0] =~ /[<>=]/ then
        req.shift
        req.shift
      end
      next
    else
      pkg = r
      r = req.shift
      if r =~ /[<>=]/ then
        nr = req.shift.split(':')
        if nr.length == 1 then
          nr.unshift '(none)'
        end
        if nr[1] !~ /-/ then
          ir[1] = ir[1].split('-')[0]
        end
        ver = nil
        if ir[0] == '(none)' then
          if nr[0] == '(none)' then
            ver = `#{$RPMVERCMP} #{ir[1]} #{nr[1]}`.chop
          else
            ver = '<'
          end
        else
          if nr[0] == '(none)' then
            ver = '>'
          else
            case ir[0].to_i <=> nr[0].to_i
            when -1
              ver = '<'
            when 0
              ver = `#{$RPMVERCMP} #{ir[1]} #{nr[1]}`.chop
            when 1
              ver = '>'
            end
          end
        end

        case r
        when ">"
          case ver
          when "<"
            rc = build_and_install(pkg, "-Uvh", name_stack, blacklist, log_file) 
            print_status(hTAG['NAME']) if !$VERBOSEOUT 
            case rc 
            when MOMO_LOOP, MOMO_FAILURE
              return rc
            end
          else
            next
          end
        when "="
          case ver
          when "="
            next
          else
            rc = build_and_install(pkg, "-Uvh", name_stack, blacklist, log_file) 
            print_status(hTAG['NAME']) if !$VERBOSEOUT 
            case rc 
            when MOMO_LOOP, MOMO_FAILURE
              return rc
            end
          end
        when ">="
          case ver
          when "<"
            rc = build_and_install(pkg, "-Uvh", name_stack, blacklist, log_file) 
            print_status(hTAG['NAME']) if !$VERBOSEOUT 
            case rc 
            when MOMO_LOOP, MOMO_FAILURE
              return rc
            end
          else
            next
          end
        end
      else
        req.unshift r
      end
    end
  end
  return MOMO_SUCCESS
end

=begin
--- chk_requires_strict(pkg_name)
TAG BuildPreReq, BuildRequires 行に記述されているパッ
ケージがあればそのパッケージがインストールされている
かどうか判断し、必要ならばインストールする。
rpm -ivh する関係上、sudo が password 無しで実行可能
である事。

spec ファイルのデータベースを参照する。
=end
def chk_requires_strict(hTAG, name_stack, blacklist, log_file)
  momo_debug_log("chk_requires_strict #{hTAG['NAME']}")
  result = MOMO_UNDEFINED

  name = hTAG['NAME']
  brs = $DEPGRAPH.db.specs[name].buildRequires
  if brs.nil? then
    result = MOMO_SUCCESS
    return
  end

  brs.each do |req|
    # 特定のパッケージは無視
    next if $IGNORE_BUILDREQ_PKGS.include?(req.name)

    puts "#{name} needs #{req} installed to build:" if $VERBOSEOUT

    flag = false
    if $SYSTEM_PROVIDES.has_name?(req.name) then
      provs = $SYSTEM_PROVIDES.select{|a| a.name == req.name}

      provs.each do |prov|
        if $VERBOSEOUT then
          print "    checking whether #{prov} is sufficient ..."
          STDOUT.flush
        end
        flag = resolved?(req, prov)
        break if flag
      end

      if flag then
        puts " YES" if $VERBOSEOUT
        next
      else
        puts " NO" if $VERBOSEOUT
      end
    else
      puts "    not installed" if $VERBOSEOUT
    end

    if !$DEPGRAPH.db.packages.include?(req.name) then
      log(log_file, "required package #{req.name} is not found, skip it")
      puts "required package #{req.name} is not found, skip it" if $VERBOSEOUT
      next
      # result = MOMO_FAILURE
      # return 
    end

    $DEPGRAPH.db.packages[req.name].each do |a|
      spec = $DEPGRAPH.db.specs[a.spec]
      rc = build_and_install(req.name, '-Uvh', name_stack, blacklist, 
                             log_file, spec.name)
      print_status(name) if !$VERBOSEOUT 
      case rc 
      when MOMO_LOOP, MOMO_FAILURE
        log(log_file, "failed to build or install #{spec.name}")
        puts "failed to build or install #{spec.name}" if $VERBOSEOUT
        result = rc
        return
      end
    end
  end # brs.each do |req|

  result = MOMO_SUCCESS

ensure
  momo_assert { MOMO_UNDEFINED != result }
  return result
end # def chk_requires_strict


def check_group(hTAG)
  hTAG['GROUP'].split(/,\s*/).each do |g|
    if GROUPS.rindex(g) == nil then
      if !$SCRIPT then
        print "\n#{RED}!! No such group (#{g}) !!\n"
        print "!! Please see /usr/share/doc/rpm-x.x.x/GROUPS !!#{NOCOLOR}\n"
      else
        print "\n!! No such group (#{g}) !!\n"
        print "!! Please see /usr/share/doc/rpm-x.x.x/GROUPS !!\n"
      end
    end
  end
end

# rpm-package #{pkg} が installされた状態にする。
# 必要な場合は #{pkg} を  build する。
# 
# 返値は  
#   MOMO_SUCCESS  成功
#   MOMO_SKIP     成功(既にinstall済)
#   その他       エラー
#
def build_and_install(pkg, rpmflg, name_stack, blacklist, log_file, specname=nil)  
  momo_debug_log("build_and_install pkg:#{pkg} rpmflg:#{rpmflg} specname:#{specname}")

  result = MOMO_UNDEFINED

  momo_assert{ pkg!="" }

  # 第1段階
  # install済のpackage or kernel関連のpackageは MOMO_SKIP とする

  ## !!FIXME!!  
  if (pkg =~ /^kernel\-/ &&
        pkg !~ /^kernel-(common|pcmcia-cs|doc|utils)/ ) then
    ## !!FIXME!!
    momo_debug_log("build_and_install skips #{pkg}")
    result = MOMO_SKIP
    return 
  end

  if specname then
    # すでにinstall済なら SKIP
    if $SYSTEM_PROVIDES.has_name?(pkg) then
      provs = $SYSTEM_PROVIDES.select{|a| a.name == pkg}
      req = SpecDB::DependencyData.new(pkg,
                                       $DEPGRAPH.db.specs[specname||pkg].packages[0].version,
                                       '==')
      flag = false
      provs.each do |prov|
        flag = resolved?(req, prov)
        break if flag
      end      
      if flag then
        momo_debug_log("build_and_install found #{pkg} in depgraph")
        result = MOMO_SKIP
        return 
      end
    end
  else # specname.nil?
    # すでにinstall済なら SKIP
    `rpm -q --whatprovides --queryformat "%{name}\\n" "#{pkg}"`
    if $?.to_i == 0 then
      momo_debug_log("build_and_install found #{pkg} using rpm -q")
      result = MOMO_SKIP
      return
    end
  end # specname.nil?

  # specname (または pkg )を provide しているパッケージを探索
  if !File.directory?(specname||pkg) then
    `grep -i ^provides: */*.spec | grep "#{specname||pkg}"`.each_line do |l|
      prov = l.split(/\//)[0]
      # "OBSOLETE" 等の設定ファイルがあれば SKIP
      if File.exist?("#{prov}/#{prov}.spec") and
          Dir.glob("#{prov}/TO.*") == [] and
          !File.exist?("#{prov}/OBSOLETE") and
          !File.exist?("#{prov}/SKIP") and
          !File.exist?("#{prov}/.SKIP") then
        pkg = prov
        break
      end
    end
  end
  
  #    if `grep -i '^BuildArch:.*noarch' #{specname||pkg}/#{specname||pkg}.spec` != ""
  #      return
  #    end

  if !$NONFREE && File.exist?("#{specname||pkg}/TO.Nonfree")
    result = MOMO_FAILURE
    return
  end

  # 第2段階  
  # 該当パッケージをビルドする
  #
  result = buildme(specname||pkg, name_stack, blacklist) 
  case result 
  when MOMO_SUCCESS, MOMO_SKIP
    result = MOMO_UNDEFINED
  else
    return 
  end

  # 第3段階  
  # #{pkg}をinstallする

  retrycounter = 10
  result = install_pkg(pkg, name_stack, blacklist, log_file, retrycounter)
  
ensure
  momo_assert { MOMO_UNDEFINED != result }
  momo_debug_log("build_and_install pkg:#{pkg} specname:#{specname} returns #{result}")
  return result
end

