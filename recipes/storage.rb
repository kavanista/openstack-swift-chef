#
# Author:: Judd Maltin <jmaltin@voxel.net>
# Author:: James Brinkerhoff <jwb@voxel.net>
#
# Copyright 2011-2012, Voxel dot Net Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Cookbook Name:: swift
# Recipe:: storage
#

include_recipe 'apt'

%w{xfsprogs swift-account swift-container swift-object}.each do |pkg_name|
  package pkg_name
end

## TODO Currently this assumes that there is only a single device to be formatted.
execute "partition disk" do
  command "/bin/echo -e \',,L\\n;\\n;\\n;\' | /sbin/sfdisk /dev/#{node[:openstack_swift][:device_name]}"#> /dev/null 2>&1"
  not_if "xfs_admin -u /dev/#{node[:openstack_swift][:device_name]}1"
end

execute "build filesystem" do
  command "mkfs.xfs -i size=1024 /dev/#{node[:openstack_swift][:device_name]}1"
  not_if "xfs_admin -u /dev/#{node[:openstack_swift][:device_name]}1"
end

directory "/srv/node/#{node[:openstack_swift][:device_name]}" do
  recursive true
  mode "0755"
  owner "#{node[:openstack_swift][:user]}"
  group "#{node[:openstack_swift][:group]}"
end

mount "/srv/node/#{node[:openstack_swift][:device_name]}" do
  device "/dev/#{node[:openstack_swift][:device_name]}1"
  fstype "xfs"
  options "noauto,noatime,nodiratime,nobarrier,logbufs=8"
  action [ :enable, :mount ]
  only_if "grep #{node[:openstack_swift][:device_name]}1 /proc/partitions"
end

directory "/srv/node/#{node[:openstack_swift][:device_name]}" do
  recursive true
  mode "0755"
  owner "#{node[:openstack_swift][:user]}"
  group "#{node[:openstack_swift][:group]}"
end

template "/etc/rsyncd.conf" do
  source "rsyncd.conf.erb"
end

cookbook_file "/etc/default/rsync" do
  source "default-rsync"
end

service "rsync" do
  supports :status => true, :restart => true, :reload => true
  action [ :enable, :start ]
end

# setup the swift configuration files

%w{/etc/swift/object-server /etc/swift/container-server /etc/swift/account-server /var/run/swift}.each do |new_dir|
  directory new_dir do
    recursive true
    owner node[:openstack_swift][:user]
    group node[:openstack_swift][:group]
    recursive true
    mode "0755"
  end
end

%w{account container object}.each do |server_type|
  template "/etc/swift/#{server_type}-server.conf" do
    source "#{server_type}-server-conf.erb"
     mode "0644"
     owner node[:openstack_swift][:user]
     group node[:openstack_swift][:group]
  end
end

directory "/etc/swift" do
  recursive true
  owner node[:openstack_swift][:user]
  group node[:openstack_swift][:group]
  mode "0755"
end

%w{ swift-object swift-object-replicator swift-object-updater swift-object-auditor swift-container swift-container-replicator swift-container-updater swift-container-auditor swift-account swift-account-replicator swift-account-auditor }.each do |component|
  service component do
    supports :restart => true, :reload => true, :start => true, :stop => true, :status => false
    action [ :enable, :start ]
  end
end

