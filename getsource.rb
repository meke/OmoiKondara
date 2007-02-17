#
#
# get_no          NoSource/NoPatch�����ǻ��ꤵ�줿�ե������ 
#                 SOURCES �ʲ����Ѱդ���
#
# cp_to_tree      Sourece/Patch/Icon �����ǻ��ꤵ��Ƥ���ե������
#                 SOURCES �ʲ����Ѱդ���


=begin
--- get_no(source_or_patch)
NoSource/NoPatch �����ǻ��ꤵ��Ƥ��륽����/�ѥå���
SOURCES �ǥ��쥯�ȥ���Ѱդ��롣������˴���¸�ߤ�
����Ϥ������Ѥ���̵�����Τߵ��Ҥ���Ƥ��� URL
����������롣�ɤ���ˤ�̵�����ϥߥ顼�����Ȥ����
�����롣
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
Sourece/Patch/Icon �����ǻ��ꤵ��Ƥ���ե������ӥ��
�ĥ꡼�˥��ԡ����롣���Ǥ�¸�ߤ���ݤˤ� co ����Ƥ���
ʪ����Ӥ��㤦ʪ�ξ��ϥ��ԡ�����
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
          md5SRC = `md5sum #{v}`.split[0]
          md5DEST = `md5sum SOURCES/#{v}`.split[0]
          exec_command("cp -pfv #{v} SOURCES",log_file) if md5SRC != md5DEST
        end
      end
    end
  end
  Dir.chdir ".."
end

# ----------- �ʲ����֥롼����


=begin
--- get_from_mirror(filename)
�����ǻ��ꤵ�줿�ե������ߥ顼�����Ȥ���������롣
.OmoiKondara �� MIRROR �ǵ��Ҥ���Ƥ��� URL �� SOURCES/
��ä�����꤫���������
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
    if File.exist?("#{hTAG['NAME']}/SOURCES/#{n}") then
      md5SRC = `md5sum #{topdir}/SOURCES/#{n}`.split[0]
      md5DEST = `md5sum #{hTAG['NAME']}/SOURCES/#{n}`.split[0]
      return true if md5SRC == md5DEST
    end
    exec_command("cp -pfv #{topdir}/SOURCES/#{n} #{hTAG['NAME']}/SOURCES", log_file)
    return true
  end
  exec_command("echo #{topdir}/SOURCES/#{n} is missing", log_file)
  return false
end
