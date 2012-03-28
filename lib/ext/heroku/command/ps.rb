require "heroku/command/base"

# manage processes (dynos, workers)
#
class Heroku::Command::Ps < Heroku::Command::Base

  # ps:dynos [QTY]
  #
  # DEPRECATED: use `heroku ps:scale dynos=N`
  #
  # scale to QTY web processes
  #
  # if QTY is not specified, display the number of web processes currently running
  #
  def dynos
    # deprecation notice added to v2.21.3 on 03/16/12
    style_warning("`heroku ps:dynos QTY` has been deprecated and replaced with `heroku ps:scale dynos=QTY`")
    if dynos = args.shift
      current = heroku.set_dynos(app, dynos)
      display "#{app} now running #{quantify("dyno", current)}"
    else
      info = heroku.info(app)
      raise(Heroku::Command::CommandFailed, "For Cedar apps, use `heroku ps`")  if info[:stack] == "cedar"
      display "#{app} is running #{quantify("dyno", info[:dynos])}"
    end
  end

  alias_command "dynos", "ps:dynos"

  # ps:workers [QTY]
  #
  # DEPRECATED: use `heroku ps:scale workers=N`
  #
  # scale to QTY background processes
  #
  # if QTY is not specified, display the number of background processes currently running
  #
  def workers
    # deprecation notice added to v2.21.3 on 03/16/12
    style_warning("`heroku ps:workers QTY` has been deprecated and replaced with `heroku ps:scale workers=QTY`")
    if workers = args.shift
      current = heroku.set_workers(app, workers)
      display "#{app} now running #{quantify("worker", current)}"
    else
      info = heroku.info(app)
      raise(Heroku::Command::CommandFailed, "For Cedar apps, use `heroku ps`")  if info[:stack] == "cedar"
      display "#{app} is running #{quantify("worker", info[:workers])}"
    end
  end

  alias_command "workers", "ps:workers"

  # ps
  #
  # list processes for an app
  #
  def index
    ps = heroku.ps(app)

    style_info("#{app} processes by command")
    data = Hash.new {|hash,key| hash[key] = {}}
    ps.each do |p|
      data["`#{p['command']}`"][p['process']] = "#{p['state']} for #{time_ago(p['elapsed']).gsub(/ ago/, "")}"
    end
    display_object(data)
  end

  # ps:restart [PROCESS]
  #
  # restart an app process
  #
  # if PROCESS is not specified, restarts all processes on the app
  #
  def restart
    opts = case args.first
    when NilClass then
      display "Restarting processes... ", false
      {}
    when /.+\..+/
      ps = args.first
      display "Restarting #{ps} process... ", false
      { :ps => ps }
    else
      type = args.first
      display "Restarting #{type} processes... ", false
      { :type => type }
    end
    heroku.ps_restart(app, opts)
    display "done"
  end

  alias_command "restart", "ps:restart"

  # ps:scale PROCESS1=AMOUNT1 ...
  #
  # scale processes by the given amount
  #
  # Example: heroku ps:scale web=3 worker+1
  #
  def scale
    current_process = nil
    changes = args.inject({}) do |hash, process_amount|
      if process_amount =~ /^([a-zA-Z0-9_]+)([=+-]\d+)$/
        hash[$1] = $2
      end
      hash
    end

    error "Usage: heroku ps:scale web=2 worker+1" if changes.empty?

    changes.each do |process, amount|
      display "Scaling #{process} processes... ", false
      amount.gsub!("=", "")
      new_qty = heroku.ps_scale(app, :type => process, :qty => amount)
      display "done, now running #{new_qty}"
    end
  end

  alias_command "scale", "ps:scale"

  # ps:stop PROCESS
  #
  # stop an app process
  #
  # Example: heroku stop run.3
  #
  def stop
    opt =
      if (args.first =~ /.+\..+/)
        ps = args.first
        display "Stopping #{ps} process... ", false
        {:ps => ps}
      elsif args.first
        type = args.first
        display "Stopping #{type} processes... ", false
        {:type => type}
      else
        error "Usage: heroku ps:stop PROCESS"
      end

    heroku.ps_stop(app, opt)
    display "done"
  end

  alias_command "stop", "ps:stop"
end
