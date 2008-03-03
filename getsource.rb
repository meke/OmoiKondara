#
#
# get_no          NoSource/NoPatchタグで指定されたファイルを 
#                 SOURCES 以下に用意する
#
# cp_to_tree      Source/Patch/Icon タグで指定されているファイルを
#                 SOURCES 以下に用意する


=begin
--- get_no(source_or_patch)
NoSource/NoPatch タグで指定されているソース/パッチを
SOURCES ディレクトリに用意する。ローカルに既に存在す
る場合はそれを使用し、無い場合のみ記述されている URL
から取得する。どちらにも無い場合はミラーサイトから取
得する。
=end
def get_no(hTAG, type, log_file)
  unless hTAG.key?("NO#{type}")
    return true
  end
  nosrc = hTAG["NO#{type}"].split(/[\s,]/)
  nosrc.delete ""
  status = 0
  nosrc.each do |no|
    file = hTAG["#{type}#{no}"]
    file = hTAG["#{type}"] if no == "0" and file.nil?
    if file =~ /^(ftp|https?):\/\// then
      n = file.split(/\//)[-1]
      if !cp_local(hTAG, n, log_file) then
        Dir.chdir "#{hTAG['NAME']}/SOURCES"
        status = -1
        if $MIRROR_FIRST then
          status = get_from_mirror(n, log_file)
        end
        if status.nonzero? then
          status = 0
          re = nil
          $URL_ALIAS.each_key do |key|
            if key.match(file) then
              re = key
              break
            end
          end
          file.sub!(re, $URL_ALIAS[re]) if re
          status = exec_command("#{$FTP_CMD} '#{file}'", log_file)
          if status.nonzero? and !$MIRROR_FIRST
            # file retrieve error
            status = get_from_mirror(n, log_file)
          end
        end
        Dir.chdir "../.."
      end
    else
      if !cp_local(hTAG, file, log_file) then
        Dir.chdir "#{hTAG['NAME']}/SOURCES"
        status = get_from_mirror(file, log_file)
        Dir.chdir "../.."
      end
    end
    return false if status.nonzero?
  end
  return status.zero?
end

=begin
--- cp_to_tree
Sourece/Patch/Icon タグで指定されているファイルをビルド
ツリーにコピーする。すでに存在する際には co されている
物と比較し違う物の場合はコピーする
=end
def cp_to_tree(hTAG, log_file)
  Dir.chdir hTAG['NAME']
  hTAG.each do |t, v|
    if t =~ /^(SOURCE|PATCH|ICON)\d*/ then
      v = v.split(/\//)[-1] if v =~ /\//
      if !File.exist?("SOURCES/#{v}") then
        ret = exec_command("cp -pfv #{v} SOURCES", log_file)
        throw(:exit_buildme, MOMO_FAILURE) if ret != 0
      else
        if File.exist?(v) then
          sha2SRC = `sha256sum #{v}`.split[0]
          sha2DST = `sha256sum SOURCES/#{v}`.split[0]
          exec_command("cp -pfv #{v} SOURCES",log_file) if sha2SRC != sha2DST
        end
      end
    end
  end
  Dir.chdir ".."
end

# ----------- 以下サブルーチン


=begin
--- get_from_mirror(filename)
引数で指定されたファイルをミラーサイトから取得する。
.OmoiKondara に MIRROR で記述されている URL に SOURCES/
を加えた場所から取得する
=end
def get_from_mirror(n, log_file)
  $MIRROR.each do |m|
    return 0 if exec_command("#{$FTP_CMD} '#{m}/SOURCES/#{n}'", log_file).zero?
  end
  return -1
end

def ftpsearch(file, log_file)
  searchstr = "http://ftpsearch.lycos.com/swadv/AdvResults.asp?form=advanced&query=#{file}&doit=Search&hits=20"
  searchstr += "&limdom=#{DOMAIN}" if DOMAIN != ""
  candidate = []
  i = RETRY_FTPSEARCH
  while candidate == [] && (i -= 1) > 0
    result = `w3m -dump "#{searchstr}"`
    strip_result = result.scan(/\d+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\S+)\s+(\S+)/)
    candidate = strip_result.delete_if do |site, path|
      path !~ /#{file}/
    end
  end
  candidate.each do |site, path|
    url = "ftp://#{site}#{path}"
    return 0 if exec_command("#{$FTP_CMD} '#{url}'", log_file).zero?
  end
  return -1
end

def cp_local(hTAG, n, log_file)
  topdir = get_topdir(hTAG['NAME'])
  if File.exist?("#{topdir}/SOURCES/#{n}") then
    if $FORCE_FETCH then
      File.unlink("#{topdir}/SOURCES/#{n}")
      return false
    end
    if File.exist?("#{hTAG['NAME']}/SOURCES/#{n}") then
      sha2SRC = `sha256sum #{topdir}/SOURCES/#{n}`.split[0]
      sha2DST = `sha256sum #{hTAG['NAME']}/SOURCES/#{n}`.split[0]
      
      if sha2SRC == sha2DST then
        return true
      else 
        throw(:exit_buildme, MOMO_CHECKSUM)
      end
    end
    exec_command("cp -pfv #{topdir}/SOURCES/#{n} #{hTAG['NAME']}/SOURCES", log_file)
    return true
  end
  exec_command("echo #{topdir}/SOURCES/#{n} is missing", log_file)
  return false
end
