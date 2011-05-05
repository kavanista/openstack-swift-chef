
# Cookbook Name:: cloudfiles
# Recipe:: default
#
# Copyright 2010, Opscode, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe 'apt'

package "python-software-properties" do
	action :install
end

apt_repository "swift-core-ppa" do
	uri "http://ppa.launchpad.net/swift-core/ppa/ubuntu"
	keyserver "keyserver.ubuntu.com"
	key "3FD32ED0E38B0CFA59495557C842BD46562598B4"
  distribution node[:lsb][:codename]
  components ["main"]
  action :add
end

execute "add openstack repo" do
	command "add-apt-repository ppa:swift-core/ppa"
	command "apt-get update"
	not_if "file /etc/apt/sources.list.d/swift-core-ppa-lucid.list"
end

%w{swift openssh-server}.each do |pkg_name|
  package pkg_name
end

# setup the swift configuration files
cookbook_file "/etc/swift/swift.conf" do
  source "swift.conf"
end

