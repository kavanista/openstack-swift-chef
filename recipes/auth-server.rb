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
# Recipe:: auth-server
#

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

