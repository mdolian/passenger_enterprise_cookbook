#
# Cookbook Name:: passenger_enterprise
# Recipe:: cleanup_passenger
#

# This renders a commented out stack.conf file
template "/etc/nginx/stack.conf" do
  owner node.ssh_username
  group node.ssh_username
  mode 0644
  source "nginx_stack.conf.erb"

  variables(
    :stack_type   => "Passenger Enterprise Standalone",
    :user         => node.ssh_username
  )
end
