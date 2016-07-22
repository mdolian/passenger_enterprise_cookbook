#
# Cookbook Name:: passenger_enterprise
# Recipe:: default
#

include_recipe "passenger_enterprise::install"
include_recipe "passenger_enterprise::monitoring"
include_recipe "passenger_enterprise::cleanup_passenger"
