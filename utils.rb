############ Sub functions ############

begin
  require 'rpmmodule'
  $CANNOTSTRICT = false

  module RPM
    class Version
      alias_method :cmp, '<=>'
      def <=>(other)
        rv = 0
        if self.e then
          if other.e.nil? then
            rv = 1
          else
            rv = self.e <=> other.e
            if rv == 0 then
              rv = cmp(other)
            end
          end
        else # self.e.nil?
          if other.e then
            rv = -1
          else
            rv = cmp(other)
          end
        end
        rv
      end # def <=>(other)
    end # class Version
  end # module RPM
rescue LoadError
  $CANNOTSTRICT = true
end

def momo_assert
  raise "Assertion failed !" unless yield
end

def momo_debug_log(msg)
  STDERR.puts msg if $DEBUG_FLAG
end

=begin
---  exec_command(command, timeout = false)
引数で指定されたコマンドを実行し、出力をログに記録する。timeoutがtrue の
場合には、タイムアウトするgets (gets_with_timeout) を使って、標準出力 を
閉じずに終わってしまう子プロセスがdefunctになるのを防ぐ。
=end
def exec_command(cmd, log_file, timeout = false)
  momo_assert{ nil != log_file }

  status = nil
  open("#{log_file}", "a") do |fLOG|
    fLOG.sync = true
    if !$SCRIPT then
      fLOG.print "\n--[#{GREEN}#{cmd}#{NOCOLOR}]--\n"
      print "\n--[#{GREEN}#{cmd}#{NOCOLOR}]--\n" if $VERBOSEOUT
    else
      fLOG.print "\n--[#{cmd}]--\n"
      print "\n--[#{cmd}]--\n" if $VERBOSEOUT
    end
    begin
      times_start = Process.times
      time_start = Time.now
      pipe = IO.pipe
      pid = Process.fork do
        pipe[0].close
        begin
          STDOUT.reopen(pipe[1])
          STDERR.reopen(pipe[1])
          pipe[1].close
          exec(cmd) rescue exit!(1)
        end
      end
      pipe[1].close
      
      begin
        while s = (timeout ? pipe[0].gets_with_timeout(60) : pipe[0].gets) do
          print s if $VERBOSEOUT
          fLOG.print s
        end
        Process.waitpid(pid)
      rescue TimeoutError
        retry until Process.waitpid(pid, Process::WNOHANG)
        fLOG.print "\nExecution timed out\n"
        print "\nExecution timed out\n" if $VERBOSEOUT
      end
    ensure
      status = $?
      pipe[0].close
      times_end = Process.times
      time_end = Time.now
      timestr = "\n--real:#{'%.2f' % (time_end - time_start)} utime:#{'%.2f' % (times_end.cutime - times_start.cutime)} stime:#{'%.2f' % (times_end.cstime - times_start.cstime)}"
      fLOG.puts timestr
      puts timestr if $VERBOSEOUT
    end
  end # open
  status.to_i
end


=begin
--- IO::gets_with_timeout (sec)
getsするが、sec秒以内に終了しない場合にはTimeoutErrorをraiseする。
=end
class IO
  def gets_with_timeout (sec)
    r = ''
    timeout (sec) do
      r = gets
    end
    r
  end
end

def get_topdir(specname, cwd = "")
  topdir = File.expand_path $TOPDIR
  if cwd != "" then
    todir = Dir.glob("#{cwd}/#{specname}/TO.*").sort
  else
    todir = Dir.glob("#{specname}/TO.*").sort
  end
  if todir != [] then
    topdir = topdir + "-" + todir[0].split(/\./)[-1]
  end
  return topdir
end


# --- ディレクトリ作成系

=begin
--- prepare_dirs(directories)
引数で指定されたディレクトリを作成する
=end
def prepare_dirs(hTAG, directories)
  Dir.chdir hTAG["NAME"]
  directories.each do |d|
    i = 0
    d.split("/").each do |cd|
      Dir.mkdir cd, 0755 unless File.directory?(cd)
      Dir.chdir cd
      i += 1
    end
    while i != 0 do
      Dir.chdir ".."
      i -= 1
    end
  end
  Dir.chdir ".."
end


