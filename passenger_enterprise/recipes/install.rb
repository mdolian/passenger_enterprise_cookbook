#
# Cookbook Name:: passenger_enterprise
# Recipe:: install
#

# Only run on app/web instances
if app_server?

  # Notify dashboard
  ey_cloud_report "passenger_enterprise" do
    message "Processing Passenger Enterprise"
  end

  # Grab version, ssh user, rails_env and port
  version       = node['passenger_enterprise']['version']
  ssh_username  = node['owner_name']
  framework_env = node['environment']['framework_env']
  port          = node['passenger_enterprise']['port']

  # Install gems required by Passenger standalone
  ruby_block "gems to install" do
    block do
      system("gem install daemon_controller rack --no-ri --no-rdoc")
    end
  end

  service "nginx" do
    action :nothing
    supports :status => false, :restart => true
  end

  # Render license file
  remote_file "/etc/passenger-enterprise-license" do
    source "passenger-enterprise-license-#{framework_env}"
    owner ssh_username
    group ssh_username
    mode "0655"
    backup 0
    not_if { FileTest.exists?("/etc/passenger-enterprise-license") }
  end

  # Download passenger enterprise tarball
  remote_file "/data/passenger-enterprise-server-#{version}.tar.gz" do
    source "https://download:#{node['passenger_enterprise']['password']}@www.phusionpassenger.com/orders/download?dir=#{version}&file=passenger-enterprise-server-#{version}.tar.gz"
    owner ssh_username
    group ssh_username
    mode "0655"
    backup 0
    not_if { FileTest.exists?("/data/passenger-enterprise-server-#{version}.tar.gz") }
  end

  # Unpackage passenger enterprise tarball to /opt
  execute "unpackage-passenger-enterprise" do
    command "cd /data && tar -zxvf passenger-enterprise-server-#{version}.tar.gz -C /opt/ && chown -R root:root /opt/passenger-enterprise-server-#{version}"
    not_if { FileTest.exists?("/opt/passenger-enterprise-server-#{version}/README.md") }
  end

  # Update /etc/motd to include information about passenger enterprise
  execute "add-passenger-enterprise-info-to-motd" do
    command "echo '\n\nNOTICE:  This instance is running Passenger Enterprise Standalone Edition v#{version}.\nPassenger binaries can be used as normal as the PATH has been prepended with the enterprise path. Binaries are located in /opt/passenger-enterprise-server-#{version}' >> /etc/motd"
    not_if "cat /etc/motd | grep NOTICE:"
  end

  # Replace existing passenger scripts with a script to call enterprise scripts
  %w[/usr/bin/passenger /usr/bin/passenger-config /usr/sbin/passenger-memory-stats /usr/sbin/passenger-status].each do |script|
    template script do
      source  'passenger-script.erb'
      owner   "root"
      group   "root"
      mode    0755
      backup  0
      variables(:script => script.split("/").last,
                :version => version)
    end
  end

  # Write out the advanced configuration file
  # From the Passenger Standalone documentation:
  # Please note that changes to this file only last until you reinstall or upgrade Phusion Passenger.
  # We are currently working on a mechanism for permanently editing the configuration file.
  remote_file "/opt/passenger-enterprise-server-4.0.37/resources/templates/standalone/config.erb" do
    owner ssh_username
    group ssh_username
    mode 0644
    source "config.erb"
    action :create
  end

  node.apps.each_with_index do |app,index|
    app_path      = "/data/#{app.name}"
    log_file      = "#{app_path}/shared/log/passenger.log"

    # Get nginx http and https ports, memory limits and worker counts.  Uses metadata if it exists.
    nginx_http_port = (meta = node.apps.detect {|a| a.metadata?(:nginx_http_port) } and meta.metadata?(:nginx_http_port)) || (node.solo? ? 80 : 81)
    nginx_https_port = (meta = node.apps.detect {|a| a.metadata?(:nginx_https_port) } and meta.metadata?(:nginx_https_port)) || (node.solo? ? 443 : 444)
    # :app_memory_limit is no longer used but is checked here and overridden when :worker_memory_size is available
    depreciated_memory_limit = metadata_app_get_with_default(app.name, :app_memory_limit, "255.0")
    # See https://support.cloud.engineyard.com/entries/23852283-Worker-Allocation-on-Engine-Yard-Cloud for more details
    memory_limit = metadata_app_get_with_default(app.name, :worker_memory_size, depreciated_memory_limit)
    memory_option = memory_limit ? "-l #{memory_limit}" : ""
    worker_count = get_pool_size

    # Render the http Nginx vhost
    template "/data/nginx/servers/#{app.name}.conf" do
      owner ssh_username
      group ssh_username
      mode 0644
      source "nginx_app.conf.erb"
      cookbook "passenger_enterprise"
      variables({
        :vhost => app.vhosts.first,
        :port => nginx_http_port,
        :upstream_port => port,
        :framework_env => framework_env
      })
      notifies :restart, resources(:service => "nginx"), :delayed
    end

    # Render proxy.conf
    remote_file "/etc/nginx/common/proxy.conf" do
      owner ssh_username
      group ssh_username
      mode 0644
      source "proxy.conf"
      action :create
      notifies :restart, resources(:service => "nginx"), :delayed
    end

    # If certificates have been added, render the https Nginx vhost and custom config
    if app.vhosts.first.https?
      file "/data/nginx/servers/#{app.name}/custom.ssl.conf" do
        action :create_if_missing
        owner node.ssh_username
        group node.ssh_username
        mode 0644
      end

      template "/data/nginx/servers/#{app.name}.ssl.conf" do
        owner node.ssh_username
        group node.ssh_username
        mode 0644
        source "nginx_app.conf.erb"
        variables({
          :vhost => app.vhosts.first,
          :ssl => true,
          :port => nginx_https_port,
          :upstream_port => port,
          :framework_env => framework_env
        })
        notifies :restart, resources(:service => "nginx"), :delayed
      end
    end

    # Render app control script, this script calls the passenger enterprise binaries using the full path
    template "/engineyard/bin/app_#{app.name}" do
      source  'app_control.erb'
      owner   ssh_username
      group   ssh_username
      mode    0755
      backup  0
      variables(:user => ssh_username,
                :app_name => app.name,
                :version  => version,
                :port     => port,
                :worker_count  => worker_count,
                :rails_env     => framework_env)
    end

    # Setup log rotate for passenger.log
    logrotate "passenger_enterprise_#{app.name}" do
      files log_file
      copy_then_truncate
    end

    # Render monitrc file to watch standalone passenger
    template "/etc/monit.d/passenger_enterprise_#{app.name}.monitrc" do
      source "passenger_enterprise.monitrc.erb"
      owner "root"
      group "root"
      mode 0666
      backup 0
      variables(:app => app.name,
                :app_memory_limit => memory_limit,
                :username => ssh_username,
                :port => port,
                :version => version)
    end

  end

  # Render passenger_monitor script
  remote_file "/engineyard/bin/passenger_monitor" do
    source "passenger_monitor"
    owner node['owner_name']
    group node['owner_name']
    mode "0655"
    backup 0
  end

  # Reload monit after making changes
  execute "monit-reload" do
    command "monit quit && telinit q"
  end

end
