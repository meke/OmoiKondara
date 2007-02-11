# strip_spec()
# make_hTAG()
#
# spec の内容（TAGとその値）を ハッシュとして返す関数
# 両者の違いは，DEPGRAPHを使う(make_hTAG)か，使わない(strip_spec)かにある．
#
# デフォルトでは make_hTAG が使われる．

=begin
--- strip_spec(spec_as_string)

文字列specをパースして，TAG(key)とその値(value)からなるハッシュを返す

処理内容としては，%define および %global 行を切り出し spec 中のマクロを
置き換えるName TAG や Version TAG など他の TAG で使用される可能性のあ
る物は置き換えて、Hash hTAG を生成する。その際に、TAG名 はすべて大文字
として格納する。

buildmeから呼ばれる
=end
def strip_spec(spec)
  macro = {}
  spec.scan(/^%(?:define|global)\s+(\S+)\s+(\S+)\s*$/) {|k, v| macro[k] = v }
  open("/usr/lib/rpm/macros") do |io|
    io.read.scan(/^%(\S+)\s+(.+)\s*$/) do |k, v|
      macro[k] = v unless k =~ /__/ or v =~ /\\/
    end
  end
  macro["nil"] = ""
  macro["_ipv6"]  = "1"
  macro["ix86"]   = "i386 i486 i586 i686 i786 i886 i986"
  macro["alpha"]  = "alpha alphaev5 alphaev56 alphapca56 alphaev6 alphaev67"
  macro["mipsel"] = "mipsel mips"
  spec = pre_process_strip(spec, macro)
  name = expand_macros(spec.scan(/^name\s*:\s*(\S+)\s*$/i)[0][0], macro)
  version = expand_macros(spec.scan(/^version\s*:\s*(\S+)\s*$/i)[0][0], macro)
  release = expand_macros(spec.scan(/^release\s*:\s*(\S+)\s*$/i)[0][0], macro)
  macro["name"] = macro["PACKAGE_NAME"] = name
  macro["version"] = macro["PACKAGE_VERSION"] = version
  macro["release"] = macro["PACKAGE_RELEASE"] = release
  
  hTAG = {}
  tag = spec.scan(/^%((?:No)?(?:Source|Patch))\s+(\d+)\s+(\S+)\s+(\S+)/)
  tag.each do |name, no, url, md5|
    no = expand_macros(no, macro)
    url = expand_macros(url, macro)
    md5 = expand_macros(md5, macro)
    case name
    when /Source/
      key = "SOURCE#{no}"
    when /Patch/
      key = "PATCH#{no}"
    end
    hTAG[key] = url
    
    if name =~ /No/ then
      key = name.upcase
      if hTAG.key?(key) then
        hTAG[key] = "#{hTAG[key]}, #{no}"
      else
        hTAG[key] = no
      end
    end
  end
  spec.scan(/^(\w+?)(?:\([^\)]+\))?\s*:(.*)$/) do |key, value|
    key.strip!
    key.upcase!
    value.strip!
    value = expand_macros(value, macro)
    if hTAG.key?(key) then
      hTAG[key] = "#{hTAG[key]}, #{value}"
    else
      hTAG[key] = value
    end
  end

  return hTAG
end

#
# DEPGRAPH を使い，パッケージ名 #{name} の specfile中の
# TAG(key)とその値(value)からなるハッシュを返す
#
# buildmeから呼ばれる
#
def make_hTAG(name)
  hTAG = {}
  hTAG['NAME'] = $DEPGRAPH.db.specs[name].name
  hTAG['VERSION'] = $DEPGRAPH.db.specs[name].packages[0].version.v
  hTAG['RELEASE'] = $DEPGRAPH.db.specs[name].packages[0].version.r
  hTAG['EPOCH'] = $DEPGRAPH.db.specs[name].packages[0].version.e
  hTAG['GROUP'] = $DEPGRAPH.db.specs[name].packages.
    collect {|pkgdat| pkgdat.group}.join(', ')
  nosource = []
  nopatch = []
  $DEPGRAPH.db.specs[name].sources.each do |src|
    case src
    when RPM::Patch
      hTAG["PATCH#{src.num}"] = src.fullname
      nopatch << src.num if src.no?
    when RPM::Icon
      hTAG["ICON#{src.num}"] = src.fullname
      nopatch << src.num if src.no?
    else
      hTAG["SOURCE#{src.num}"] = src.fullname
      nosource << src.num if src.no?
    end
  end
  hTAG['NOSOURCE'] = nosource.join(', ')
  hTAG['NOPATCH'] = nopatch.join(', ')
  hTAG['BUILDARCH'] = $DEPGRAPH.db.specs[name].archs.join(', ')

  return hTAG
end # def make_hTAG(name)


#
# strip_spec内部で利用されるサブルーチン
# 
def pre_process_strip(spec, macros={})
  s = ""
  stack = [true]
  spec.each_line do |line|
    if line =~ /(^|[^%])%if(\S*)\s+(.+)/ then
      cond, value = $2, $3
      value = expand_macros(value, macros)
      case cond
      when "arch"
        stack.push(value =~ /#{$ARCHITECTURE}/)
      when "narch"
        stack.push(value !~ /#{$ARCHITECTURE}/)
      when "os"
        stack.push(value =~ /#{$OS}/)
      else
        if cond == "" then
          stack.push(value !~ /0/ && value =~ /\!\s*0/)
        end
      end
    else
      case line
      when /(^|[^%])%endif/
        stack.pop
      when /(^|[^%])%else/
        stack[-1] = !stack[-1] if stack.size > 0
      else
        if stack.last then
          line.gsub!(/(^|[^%])%\{\?(\w+?):(\w+?)\}/){ macros.has_key?($2) ? $3 : "" }
          s += line if stack.last
        end
      end
    end
  end
  return s
end

#
# strip_spec内部で利用されるサブルーチン
# 
def expand_macros(str, macros={})
  str = str.dup
  while str =~ /%/ do
    case str
    when /%(\w+)/ then
      m = $1
      if macros.has_key?(m) then
        str.gsub!(/%#{m}/, macros[m])
      else
        macros[m] = ""
      end
    when /%\{([_\w]+?)\}/ then
      m = $1
      if macros.has_key?(m) then
        str.gsub!(/%\{#{m}\}/, macros[m])
      else
        macros[m] = ""
      end
    when /%\(([^)]+)\)/ then
      shcmd = $1
      res = `#{shcmd}`.chomp
      shcmd = Regexp.quote(shcmd)
      str.gsub!(/%\(#{shcmd}\)/, res)
    when /%\{(\!)?\?([_\w]+?)(:([\-\._\w]+?))?\}/ then
      flag = $1
      m = $2
      negative = $4 || ''
      if macros.has_key?( m ) then
        positive = macros[m]
      else
        positive = ''
      end
      unless flag then
        res = positive
      else
        res = negative
      end
      str.gsub!( /%\{\!?\?.+?\}/, res )
    else
      raise "Failed to expand macro(s): `#{str}'"
    end
  end
  str
end

