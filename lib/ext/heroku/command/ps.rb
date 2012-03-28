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
      style_action("scaling #{app} to #{quantify("dyno", current)}")
      current = heroku.set_dynos(app, dynos)
      hputs("done")
    else
      info = heroku.info(app)
      raise(Heroku::Command::CommandFailed, "For Cedar apps, use `heroku ps`")  if info[:stack] == "cedar"
      style_info("#{app} is running #{quantify("dyno", info[:dynos])}")
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
      style_action("scaling #{app} to #{quantify("worker", current)}")
      current = heroku.set_workers(app, workers)
      hputs("done")
    else
      info = heroku.info(app)
      raise(Heroku::Command::CommandFailed, "For Cedar apps, use `heroku ps`")  if info[:stack] == "cedar"
      style_info("#{app} is running #{quantify("worker", info[:workers])}")
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
      style_action("Restarting processes")
      {}
    when /.+\..+/
      ps = args.first
      style_action("Restarting #{ps} process")
      { :ps => ps }
    else
      type = args.first
      style_action("Restarting #{type} processes")
      { :type => type }
    end
    heroku.ps_restart(app, opts)
    hputs("done")
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
      style_action("scaling #{process} processes")
      amount.gsub!("=", "")
      new_qty = heroku.ps_scale(app, :type => process, :qty => amount)
      hputs("done, now running #{new_qty}")
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
        style_action("stopping #{ps} process")
        {:ps => ps}
      elsif args.first
        type = args.first
        style_action("stopping #{type} processes")
        {:type => type}
      else
        error "Usage: heroku ps:stop PROCESS"
      end

    heroku.ps_stop(app, opt)
    hputs("done")
  end

  alias_command "stop", "ps:stop"
end
