# depgraph 系
#

begin
  begin
    load '../tools/v2/depgraph-mini'
  rescue
    load '../tools/v2/depgraph'
  end
rescue Exception
  $CANNOTSTRICT = true
end
begin
  $DEPGRAPH = DepGraph.new(false) unless $NOSTRICT
rescue => e
  STDERR.puts e.message
  exit 1
end

def resolved?(req, prov)
  # not specify provided version
  if prov.version.nil?
    return true
  end
  flag = false
  case req.rel.to_s.strip
  when '<=' then
    flag = prov.version <= req.version
  when '<' then
    flag = prov.version < req.version
  when '>=' then
    flag = prov.version >= req.version
  when '>' then
    flag = prov.version > req.version
  when '==' then
    if req.version.r.nil? then
      flag = prov.version.v == req.version.v
    else
      flag = prov.version == req.version
    end
  else
    # not specify required version
    flag = true
  end
  flag
end # def resolved?(req, prov)
