=begin
--- chk_requires
TAG BuildPreReq, BuildRequires 行に記述されているパッ
ケージがあればそのパッケージがインストールされている
かどうか判断し、必要ならばインストールする。
rpm -ivh する関係上、sudo が password 無しで実行可能
である事。
=end
def chk_requires
  req = Array.new
  if $hTAG.key?("BUILDPREREQ") then
    req = $hTAG["BUILDPREREQ"].split(/[\s,]/)
  end
  if $hTAG.key?("BUILDREQUIRES") then
    $hTAG["BUILDREQUIRES"].split(/[\s,]/).each {|r| req.push r}
  end

  return  if req.empty?

  req.delete ""
  while r = req.shift do
    # 直接ファイル名が指定されている
    # パッケージ名を指定すべし
    next  if r =~ /\//

    # インストール済の場合 ir = <epoch>:<ver>-<rel>
    ir = `rpm -q --queryformat '%{EPOCH}:%{VERSION}-%{RELEASE}' #{r} 2>/dev/null`.split(':')
    r = r.split(/\-/)[0..-2].join("-") if r =~ /\-devel/

    if ir.length != 2 then
      if build_and_install(r, "-Uvh") == MOMO_LOOP then
        return MOMO_LOOP
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
            if build_and_install(pkg, "-Uvh") == MOMO_LOOP then
              return MOMO_LOOP
            end
          else
            next
          end
        when "="
          case ver
          when "="
            next
          else
            if build_and_install(pkg, "-Uvh") == MOMO_LOOP then
              return MOMO_LOOP
            end
          end
        when ">="
          case ver
          when "<"
            if build_and_install(pkg, "-Uvh") then
              return MOMO_LOOP
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
def chk_requires_strict(name)
  brs = $DEPGRAPH.db.specs[name].buildRequires
  return  if brs.nil?
  brs.each do |req|
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

    next unless $DEPGRAPH.db.packages[req.name]
    $DEPGRAPH.db.packages[req.name].each do |a|
      spec = $DEPGRAPH.db.specs[a.spec]
      if build_and_install(req.name, '-Uvh', spec.name) == MOMO_LOOP then
        return MOMO_LOOP
      end
    end
  end # brs.each do |req|
end # def chk_requires_strict


def check_group
  $hTAG['GROUP'].split(/,\s*/).each do |g|
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

def build_and_install(pkg, rpmflg, specname=nil)
  return if pkg == "" or (pkg =~ /^kernel\-/ &&
                            pkg !~ /^kernel-(common|pcmcia-cs|doc|utils)/ )
  if specname then
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
      return if flag
    end
  else # specname.nil?
    `rpm -q --whatprovides --queryformat "%{name}\\n" #{pkg}`
    return if $?.to_i == 0
  end # specname.nil?
  if !File.directory?(specname||pkg) then
    `grep -i ^provides: */*.spec | grep #{specname||pkg}`.each_line do |l|
      prov = l.split(/\//)[0]
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
    return
  end
  _t = $hTAG.dup
  _l = $LOG_PATH
  
  if buildme(specname||pkg) == MOMO_LOOP then
    return MOMO_LOOP
  end
  topdir = get_topdir
  $LOG_PATH = _l
  $hTAG = _t
  
  pkgs = []
  if specname and $DEPGRAPH then
    spec = $DEPGRAPH.db.specs[specname]
    pkg2 = spec.packages.select{|a| a.name == pkg}[0]
    if pkg2 then
      pkg2.requires.each do |req|
        if not $SYSTEM_PROVIDES.has_name?(req.name) then
          if $DEPGRAPH.db.packages[req.name] then
            $DEPGRAPH.db.packages[req.name].each do |a|
              build_and_install(a.spec, rpmflg)
            end
          end
        end
      end
      pkg = pkg2.name
    end
  end
  pkgs = Dir.glob("#{topdir}/#{$ARCHITECTURE}/#{pkg}-*.rpm")
  pkgs += Dir.glob("#{topdir}/noarch/#{pkg}-*.rpm")

  if /-devel/ =~ pkg then
    mainpkg = pkg.sub( /-devel/, '' )
    pkgs += Dir.glob("#{topdir}/#{$ARCHITECTURE}/#{mainpkg}-*.rpm")
    pkgs += Dir.glob("#{topdir}/noarch/#{mainpkg}-*.rpm")
  end

  if not pkgs.empty? then
    pkgs.uniq!
    ret = exec_command "rpm #{rpmflg} --force --test #{pkgs.join(' ')}"
    throw(:exit_buildme, MOMO_FAILURE) if ret != 0
    exec_command "sudo rpm #{rpmflg} --force #{pkgs.join(' ')}"

    if not $CANNOTSTRICT then
      pkgs.each do |a|
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
  end

  if !$VERBOSEOUT then
    print "#{$hTAG['NAME']} "
    print "-" * [51 - $hTAG['NAME'].length, 1].max, "> "
  end
end

