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
# Recipe:: proxy
#

## grab the major config databag
## TODO: This should pull the databag name, etc from an attribute defined by a role
data_bag("testcluster")
cluster_conf = data_bag_item("testcluster", "conf")
common_conf  = cluster_conf["ring_common"]

# install required packages
%w{swift-proxy memcached}.each do |pkg_name|
  package pkg_name
end

## TODO This should be moved to only the base (default) recipe used by all node types.
directory "/etc/swift" do
  recursive true
  owner node[:openstack_swift][:user]
  group node[:openstack_swift][:group]
  mode "0755"
end

cookbook_file "/etc/swift/cert.key" do
  source "cert.key"
  owner "swift"
end

cookbook_file "/etc/swift/cert.crt" do
  source "cert.crt"
  owner "swift"
end

## Right now we're using a static key, that's obviously not acceptable outside of testing, below are some bits we may use in the future
#execute "make ssl keys" do
#  command "cd /etc/swift; openssl req -new -x509 -nodes -out cert.crt -keyout cert.key"
#  not_if "file /etc/swift/cert.crt"
#  environment( { 'KEY_COUNTRY' => 'US', 'KEY_PROVINCE' => 'NY', 'KEY_CITY' => 'New York', 'KEY_ORG' => 'Voxel dot Net, Inc.', 'KEY_EMAIL' => 'support@voxel.net', 'KEY_CN' => 'swift.voxel.net' } )
#end

## TODO This should only listen on localhost, we need to change the proxy to access it there.
execute "fix up memcached.conf to list on proxy network interface" do
  command "perl -pi -e 's/^-l 127.0.0.1/-l 0.0.0.0/' /etc/memcached.conf"
  not_if "grep '0.0.0.0' /etc/memcached.conf"
  notifies :restart, "service[memcached]"
end

service "swift-proxy" do
  supports :start => true, :restart => true, :restart => true
  action [ :enable, :start ]
end

service "memcached" do
  supports :status => true, :start => true, :stop => true, :restart => true
  action [ :enable, :start ]
end

# make sure the template gets the right IP address too, the "proxy" network.
template "/etc/swift/proxy-server.conf" do
  source "proxy-server.conf.erb"
  mode 0644
  owner "#{node[:openstack_swift][:user]}"
  group "#{node[:openstack_swift][:group]}"
  notifies :restart, "service[swift-proxy]"
end

## TODO While the below section works for an initial spinup based upon the databag, it does not fully handle modifications to the databag and thus cluster layout over time.
##      this is something we are currently working on.

# RING MANAGEMENT
# -create # -add devices # -rebalance # -distribute

# RING CONFIG FORMAT:
# BASICS:
# <ring>  <partition power> <number of replicas> <minimum partition hours>

# check to make sure that the rings have the config settings that are in the bag.
# code here

# create the rings, if there are no rings.
%w{account object container}.each do |ringtype|
  execute "make the #{ringtype} ring" do
    command "swift-ring-builder /etc/swift/#{ringtype}.builder create " + 
      common_conf[ ringtype+'_part_power'].to_s + " " +
      common_conf[ ringtype+'_replicas'].to_s + " " +
      common_conf[ ringtype+'_min_part_hours'].to_s 
    not_if "test -f /etc/swift/#{ringtype}.builder"
  end
end

## Adds Nodes to Rings
## For each ring, marked online, call ring builder for each node in the bag/ring
## *NOTE* Only if the ring_type.builder file does not yet contain this node
## TODO: This should also locate the nodes by something a bit more specific than hostname
cluster_conf["rings"].each do |ring|
  if ring['status'] == 'online'
    search(:node, "hostname:" + ring['hostname'] ) do |storage_node|
      log "found node matching " + ring['hostname']
      log "swift-ring-builder /etc/swift/" + ring['ring_type'] + ".builder add z" + ring['zone'] + '-' + storage_node[:ipaddress] + ":" + ring['port'].to_s + "/" + ring['device'] + "_" + ring['meta'] + " " + ring['weight'].to_s + "; exit 0"

      execute "add #{storage_node[:ipaddress]} to #{ring['ring_type']}" do
        cwd '/etc/swift'
        command "swift-ring-builder /etc/swift/" + ring['ring_type'] + ".builder add z" + ring['zone'] + '-' + storage_node[:ipaddress] + ":" + ring['port'].to_s + "/" + ring['device'] + "_" + ring['meta'] + " " + ring['weight'].to_s + "; exit 0"

        notifies :run, "execute[rebalance the #{ring['ring_type']} ring]"

        not_if do
          metaname = "z" + ring['zone'] + '-' + storage_node[:ipaddress] + ":" + ring['port'].to_s + "/" + ring['device'] + "_" + ring['meta']
          `echo blah > /tmp/blee && cd /etc/swift && swift-ring-builder #{ring['ring_type']}.builder search #{metaname}`
          $? == 256   # Why is this 256?  It's what works, but I don't know why.
        end
      end
    end
  end
end

storage_nodes = search(:node, "role:swift-storage AND role:environment-#{node[:app_environment]}")

# rebalance the rings, if things have changed
%w{account object container}.each do |ringtype|
  execute "rebalance the #{ringtype} ring" do
    cwd '/etc/swift/'
    command "swift-ring-builder /etc/swift/#{ringtype}.builder rebalance"
    storage_nodes.map { |sn| notifies :run, "execute[scp rings to #{sn[:ipaddress]}]" }
    action :nothing
  end
end

# send the rings to all the nodes, if things have changed
storage_nodes.each_with_index do |storage_node, zone|
  execute "scp rings to #{storage_node[:ipaddress]}" do
    user "swift"
    cwd '/etc/swift/'
    command "scp /etc/swift/*.builder /etc/swift/*.gz swift@#{storage_node[:ipaddress]}:/etc/swift/"
    action :nothing
  end
end

