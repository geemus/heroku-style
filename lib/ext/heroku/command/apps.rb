require "heroku/command/base"

# manage apps (create, destroy)
#
class Heroku::Command::Apps < Heroku::Command::Base

  # apps
  #
  # list your apps
  #
  def index
    style_header("#{heroku.user} Apps")
    list = heroku.list
    if list.size > 0
      owned, shared = list.partition {|app, owner| owner == heroku.user}
      style_info("Owned by Me")
      style_object(owned.map {|app, owner| app})
      style_info("Shared with Me")
      style_object(shared.map {|app, owner| app})
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
    unless options[:raw]
      style_header("#{app} Info")
    end

    attrs = heroku.info(app)

    if options[:raw]
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
        'Addons'            => !attrs[:addons].empty? && attrs[:addons].map {|addon| addon['description']},
        'Create Status'     => (attrs[:create_status] != 'complete') && attrs[:create_status],
        'Cron Finished At'  => attrs[:cron_finished_at] && format_date(attrs[:cron_finished_at]),
        'Cron Next Run'     => attrs[:cron_next_run] && format_date(attrs[:cron_next_run]),
        'Database Size'     => attrs[:database_size] && format_bytes(attrs[:database_size]),
        'Domain Name'       => attrs[:domain_name],
        'Dynos'             => (attrs[:stack] != 'cedar') && attrs[:dynos],
        'Git URL'           => attrs[:git_url],
        'Owner'             => attrs[:owner],
        'Repo Size'         => attrs[:repo_size] && format_bytes(attrs[:repo_size]),
        'Slug Size'         => attrs[:slug_size] && format_bytes(attrs[:slug_size]),
        'Stack'             => attrs[:stack],
        'Web URL'           => attrs[:web_url],
        'Workers'           => (attrs[:stack] != 'cedar') && attrs[:workers],
      }
      data.reject! {|key,value| !value}

      collaborators = attrs[:collaborators].delete_if { |c| c[:email] == attrs[:owner] }
      unless collaborators.empty?
        attrs[:collaborators].reject! {|collaborator| collaborator[:email] == attrs[:owner]}
        data['Collaborators'] = attrs[:collaborators].map {|collaborator| collaborator[:email]}
      end

      if attrs[:database_tables]
        data['Database Size'].gsub!('(empty)', '0K') + " in #{quantify("table", attrs[:database_tables])}"
      end

      if attrs[:dyno_hours].is_a?(Hash)
        data['Dyno Hours'] = attrs[:dyno_hours].keys.map do |type|
          "    = %s: %0.2f dyno-hours" % [ type.to_s.capitalize, attrs[:dyno_hours][type] ]
        end
      end

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
    if name
      style_action("Creating #{name}")
    else
      style_action("Creating")
    end
    info    = heroku.create_app(name, {:stack => stack})
    name    = info["name"]
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
      hputs

      (options[:addons] || "").split(",").each do |addon|
        addon.strip!
        style_action("Adding #{addon} to #{name}")
        heroku.install_addon(name, addon)
        hputs("done")
      end

      if buildpack = options[:buildpack]
        heroku.add_config_vars(name, "BUILDPACK_URL" => buildpack)
      end

      style_object({
        "Git URL" => info["git_url"],
        "Web URL" => info["web_url"]
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

    style_action("Renaming #{app} to #{newname}")
    heroku.update(app, :name => newname)
    hputs("done")
    hputs

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
    style_action("opening #{url}")
    hputs("done")
    hputs
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
      style_action("destroying #{app} (including all add-ons)")
      heroku.destroy(app)
      if remotes = git_remotes(Dir.pwd)
        remotes.each do |remote_name, remote_app|
          next if app != remote_app
          git "remote rm #{remote_name}"
        end
      end
      hputs("done")
      hputs
    end
  end

  alias_command "destroy", "apps:destroy"
  alias_command "apps:delete", "apps:destroy"

end
