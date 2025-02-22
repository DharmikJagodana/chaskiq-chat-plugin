require "app_packages_catalog"

namespace :packages do
  task update: :environment do
    Rails.logger = Logger.new($stdout)
    AppPackagesCatalog.update_all
  end

  task attach: :environment do
    Rails.logger = Logger.new($stdout)
    App.find_each { |a| a.attach_default_packages }
  end

  # publish plugins to service (chaskiq only)
  task publish: :environment do
    Rails.logger = Logger.new($stdout)
    require_relative Rails.root.join("app/services/plugin_subscriptions")
    PluginSubscriptions::RemotePlugin.upload_list
  end

  # downloads and stores in DB app package/plugin
  task download: :environment do
    Rails.logger = Logger.new($stdout)
    require_relative Rails.root.join("app/services/plugin_subscriptions")
    PluginSubscriptions::PluginDownloader.new.fetch_plugin_data
    # Plugin.save_all_plugins()
  end

  # install downloaded plugins in FS
  task install: :environment do
    Rails.logger = Logger.new($stdout)
    Plugin.save_all_plugins
  end

  # rake packages:freeze['your_package_name']
  desc "Freeze an AppPackage by name"
  task :freeze, [:pkg_name] => :environment do |_task, args|
    Rails.logger = Logger.new($stdout)

    pkg_name = args[:pkg_name]

    if pkg_name.blank?
      puts "🔴 Error: You must provide a package name."
    else
      pkg = AppPackage.find_by(name: pkg_name)

      if pkg.nil?
        puts "🔴 Error: AppPackage '#{pkg_name}' not found."
      else
        pkg.freeze!
        puts "✅ AppPackage '#{pkg_name}' has been frozen."
      end
    end
  end

  desc "UnFreeze an AppPackage by name"
  task :unfreeze, [:pkg_name] => :environment do |_task, args|
    Rails.logger = Logger.new($stdout)

    pkg_name = args[:pkg_name]

    if pkg_name.blank?
      puts "🔴 Error: You must provide a package name."
    else
      pkg = AppPackage.find_by(name: pkg_name)

      if pkg.nil?
        puts "🔴 Error: AppPackage '#{pkg_name}' not found."
      else
        pkg.unfreeze!
        puts " ✅ AppPackage '#{pkg_name}' has been unfrozen."
      end
    end
  end
end

namespace :owner_apps do
  task make_owner: :environment do
    # roles owners
    App.all.each do |o|
      o.owner = Agent.find_by(email: Chaskiq::Config.fetch("ADMIN_EMAIL", nil))
      o.save
    end
  end
end

namespace :upgrade_tasks do
  # migration from bot_task model to bot_tasks < message
  task predicates: :environment do
    Message.all.each do |c|
      next if c.segments.nil?

      segments = c.segments.compact.map do |o|
        if o["attribute"] == "type"
          o.merge!({
                     "comparison" => "in",
                     "value" => o["value"].is_a?(Array) ? o["value"] : [o["value"]].flatten
                   })
        else
          o
        end
      end.compact

      c.update(segments: segments)
    end

    Segment.all.each do |c|
      next if c.predicates.nil?

      segments = c.predicates.compact.map do |o|
        if o["attribute"] == "type"
          o.merge!({
                     "comparison" => "in",
                     "value" => o["value"].is_a?(Array) ? o["value"] : [o["value"]].flatten
                   })
        else
          o
        end
      end.compact

      c.update(predicates: segments)
    end
  end

  task clean_nested_bots: :environment do
    BotTask.find_each do |bot_task|
      next if bot_task.paths.nil?

      bot_task.paths.map do |path|
        next if path["steps"].nil?

        path["steps"].map do |step|
          if step.key?("controls")
            new_controls = step["controls"]["schema"].reject do |o|
              o.key?("controls")
            end
            step.merge!({ "controls" => step["controls"].merge!({ "schema" => new_controls }) })
            step
          end
          step
        end
      end

      bot_task.save
    end
  end
end
