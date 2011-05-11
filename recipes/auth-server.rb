
# Cookbook Name:: swift
# Recipe:: auth-server
#

#include_recipe 'apt'

package "swift-auth" do
  action :install
end

template "/etc/swift/auth-server.conf" do
  source "auth-server.conf.erb"
  owner node[:openstack_swift][:user]
  group node[:openstack_swift][:user]
  variables(
    :super_admin_key => 'n0ts3cur3'
  )
end

service "swift-auth" do
  supports :start => true, :stop => true, :restart => true
  action [ :enable, :start]
end

