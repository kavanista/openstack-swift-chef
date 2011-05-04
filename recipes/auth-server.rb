
# Cookbook Name:: swift
# Recipe:: auth-server
#

#include_recipe 'apt'

execute "add auth user" do
	command "swift-auth-add-user -K #{node[:openstack_swift][:super_admin_key]} -a #{node[:openstack_swift][:admin_account]} #{node[:openstack_swift][:admin_username]} #{node[:openstack_swift][:admin_password]} "
end

# validation
script "validate the install" do
# "Get an X-Storage-Url and X-Auth-Token:" do
	command "curl -k -v -H 'X-Storage-User: system:root' -H 'X-Storage-Pass: testpass' https://localhost:11000/v1.0"
end

# validation
execute "Check that you can HEAD the account:" do
	command "curl -k -v -H 'X-Auth-Token: <token-from-x-auth-token-above>' <url-from-x-storage-url-above>"
end

# validation
execute "Check that st works" do
	command "st -A https://<AUTH_HOSTNAME>:11000/v1.0 -U system:root -K testpass stat"
end

# validation
execute " Use st to download all files from the .myfiles. container:" do
	command "st -A https://<AUTH_HOSTNAME>:11000/v1.0 -U system:root -K testpass download myfiles"
end
