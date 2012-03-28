require "heroku/command/base"

# manage apps (create, destroy)
#
class Heroku::Command::Apps < Heroku::Command::Base

  # apps
  #
  # list your apps
  #
  def index
    style_info("apps by owner")
    list = heroku.list
    if list.size > 0
      apps_by_owner = Hash.new {|hash,key| hash[key] = []}
      list.map {|name, owner| apps_by_owner[owner] << name}
      style_object(apps_by_owner)
    else
      hputs("You have no apps.")
    end
  end

  alias_command "list", "apps"

  # apps:info
  #
  # show detailed app information
  #
  # -r, --raw  # output info as raw key/value pairs
  #
  def info
    attrs = heroku.info(app)

    if options[:raw] then
      attrs.keys.sort_by { |a| a.to_s }.each do |key|
        case key
        when :addons then
          hputs("addons=#{attrs[:addons].map { |a| a["name"] }.sort.join(",")}")
        when :collaborators then
          hputs("collaborators=#{attrs[:collaborators].map { |c| c[:email] }.sort.join(",")}")
        else
          hputs("#{key}=#{attrs[key]}")
        end
      end
    else
      data = {
        'addons'            => !attrs[:addons].empty? && attrs[:addons].map {|addon| addon['description']},
        'create status'     => (attrs[:create_status] != 'complete') && attrs[:create_status],
        'cron finished at'  => attrs[:cron_finished_at] && format_date(attrs[:cron_finished_at]),
        'cron next run'     => attrs[:cron_next_run] && format_date(attrs[:cron_next_run]),
        'database size'     => attrs[:database_size] && format_bytes(attrs[:database_size]),
        'domain name'       => attrs[:domain_name],
        'dynos'             => (attrs[:stack] != 'cedar') && attrs[:dynos],
        'git url'           => attrs[:git_url],
        'owner'             => attrs[:owner],
        'repo size'         => attrs[:repo_size] && format_bytes(attrs[:repo_size]),
        'slug size'         => attrs[:slug_size] && format_bytes(attrs[:slug_size]),
        'stack'             => attrs[:stack],
        'web url'           => attrs[:web_url],
        'workers'           => (attrs[:stack] != 'cedar') && attrs[:workers],
      }
      data.reject! {|key,value| !value}

      collaborators = attrs[:collaborators].delete_if { |c| c[:email] == attrs[:owner] }
      unless collaborators.empty?
        attrs[:collaborators].reject! {|collaborator| collaborator[:email] == attrs[:owner]}
        data['collaborators'] = attrs[:collaborators].map {|collaborator| collaborator[:email]}
      end

      if attrs[:database_tables]
        data['database size'].gsub!('(empty)', '0K') + " in #{quantify("table", attrs[:database_tables])}"
      end

      if attrs[:dyno_hours].is_a?(Hash)
        data['dyno hours'] = attrs[:dyno_hours].keys.map do |type|
          "    = %s: %0.2f dyno-hours" % [ type.to_s.capitalize, attrs[:dyno_hours][type] ]
        end
      end

      style_info("#{app} info")
      style_object(data)
    end
  end

  alias_command "info", "apps:info"

  # apps:create [NAME]
  #
  # create a new app
  #
  #     --addons ADDONS        # a comma-delimited list of addons to install
  # -b, --buildpack BUILDPACK  # a buildpack url to use for this app
  # -r, --remote REMOTE        # the git remote to create, default "heroku"
  # -s, --stack STACK          # the stack on which to create the app
  #
  def create
    remote  = extract_option('--remote', 'heroku')
    stack   = extract_option('--stack', 'aspen-mri-1.8.6')
    timeout = extract_option('--timeout', 30).to_i
    name    = args.shift.downcase.strip rescue nil
    info    = heroku.create_app(name, {:stack => stack})
    name = info["name"]
    style_action("creating #{name}")
    begin
      if info["create_status"] == "creating"
        Timeout::timeout(timeout) do
          loop do
            break if heroku.create_complete?(name)
            hprint(".")
            sleep 1
          end
        end
      end
      hputs("done, stack is #{info["stack"]}")

      (options[:addons] || "").split(",").each do |addon|
        addon.strip!
        style_action("adding #{addon} to #{name}")
        heroku.install_addon(name, addon)
        hputs("done")
      end

      if buildpack = options[:buildpack]
        heroku.add_config_vars(name, "BUILDPACK_URL" => buildpack)
      end

      style_object({
        :git_url => info["git_url"],
        :web_url => info["web_url"]
      })
    rescue Timeout::Error
      error("Timed Out! Check heroku status for known issues.")
    end

    create_git_remote(remote || "heroku", info["git_url"])
  end

  alias_command "create", "apps:create"

  # apps:rename NEWNAME
  #
  # rename the app
  #
  def rename
    newname = args.shift.downcase.strip rescue ''
    raise(Heroku::Command::CommandFailed, "Must specify a new name.") if newname == ''

    style_action("renaming #{app} to #{newname}")
    heroku.update(app, :name => newname)
    hputs("done")

    info = heroku.info(newname)
    style_object({
      :git_url => info["git_url"],
      :web_url => info["web_url"]
    })

    if remotes = git_remotes(Dir.pwd)
      remotes.each do |remote_name, remote_app|
        next if remote_app != app
        git "remote rm #{remote_name}"
        git "remote add #{remote_name} #{info[:git_url]}"
        hputs("Git remote #{remote_name} updated")
      end
    else
      hputs("Don't forget to update your Git remotes on any local checkouts.")
    end
  end

  alias_command "rename", "apps:rename"

  # apps:open
  #
  # open the app in a web browser
  #
  def open
    info = heroku.info(app)
    url = info[:web_url]
    action("opening #{url}")
    Launchy.open url
  end

  alias_command "open", "apps:open"

  # apps:destroy
  #
  # permanently destroy an app
  #
  def destroy
    @app = args.first || options[:app] || options[:confirm]
    unless @app
      raise Heroku::Command::CommandFailed.new("Usage: heroku apps:destroy --app APP")
    end

    heroku.info(app) # fail fast if no access or doesn't exist

    message = "WARNING: Potentially Destructive Action\nThis command will destroy #{app} (including all add-ons)."
    if confirm_command(app, message)
      action("destroying #{app} (including all add-ons)")
      heroku.destroy(app)
      if remotes = git_remotes(Dir.pwd)
        remotes.each do |remote_name, remote_app|
          next if app != remote_app
          git "remote rm #{remote_name}"
        end
      end
      hputs("done")
    end
  end

  alias_command "destroy", "apps:destroy"
  alias_command "apps:delete", "apps:destroy"

end
