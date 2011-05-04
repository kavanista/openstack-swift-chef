# setup openstack proxy servers

# grab the major config databag
data_bag("testcluster")
#log ( data_bag_item("testcluster", "conf"))
cluster_conf = data_bag_item("testcluster", "conf")
common_conf = cluster_conf["ring_common"]

# install required packages
%w{swift-proxy memcached}.each do |pkg_name|
	package pkg_name
end

# make ssl certs/keys
execute "make ssl keys" do
	command "cd /etc/swift; openssl req -new -x509 -nodes -out cert.crt -keyout cert.key"
	not_if "file /etc/swift/cert.crt"
end

# how do I find the interface I want it to listen on?  Knowing the network, and doing the math.
execute "fix up memcached.conf to list on proxy network interface" do
	command "perl -pi -e 's/^-l 127.0.0.1/-l 0.0.0.0/' /etc/memcached.conf"
	not_if "grep '0.0.0.0' /etc/memcached.conf"
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
end

# RING MANAGEMENT
# -create # -add devices # -rebalance # -distribute

# RING CONFIG FORMAT:
# BASICS:
# <ring>  <partition power> <number of replicas> <minimum partition hours>

# check to make sure that the rings have the config settings that are in the bag.
# code here

# create the rings, if there are no rings.
%w{account object container}.each do |ringtype|
	#log("swift-ring-builder /etc/swift/#{ringtype}.builder create " + common_conf[#{ringtype}+'_part_power']  )
	execute "make the #{ringtype} ring" do
		command "swift-ring-builder /etc/swift/#{ringtype}.builder create " + 
			common_conf[ ringtype+'_part_power'].to_s + " " +
			common_conf[ ringtype+'_replicas'].to_s + " " +
			common_conf[ ringtype+'_min_part_hours'].to_s 
		#command "swift-ring-builder /etc/swift/#{ringtype}.builder create #{common_conf[ #{ringtype}_part_power] } " 
		not_if "test -f /etc/swift/#{ringtype}.builder"
	end
end

# update the ring config, if they differ from the databag.

# update it from the data bag
# search for all the rings that have servers that are:
## have the storage role on the node
## marked online in the databag

cluster_conf["rings"].each do |ring|
	# search for the node with the matching hostname
	if ring['status'] == 'online'
		search(:node, "hostname:" + ring['hostname'] ) do |storage_node|
			log "found node matching " + ring['hostname']
			log "swift-ring-builder /etc/swift/" + ring['ring_type'] + ".builder add z" + 
				ring['zone'] + '-' + 
				storage_node[:ipaddress] + ":" +
				ring['port'] + "/" +
				ring['device'] + "_" +
				ring['cluster'] + "_" +
				ring['meta'] + " " +
				ring['weight'].to_s + "; exit 0"
			execute "make #{storage_node[:ipaddress]}" do
				cwd '/etc/swift/'
				##user "swift"
				command "swift-ring-builder /etc/swift/" + ring['ring_type'] + ".builder add z" + 
					ring['zone'] + '-' + 
					storage_node[:ipaddress] + ":" +
					ring['port'] + "/" +
					ring['device'] + "_" +
					ring['cluster'] + "_" +
					ring['meta'] + " " +
					ring['weight'] + "; exit 0"
        not_if "test -f /etc/swift/account.builder"
			end 	
		end
	end
end



#TODO: find approprite exit values for this

# setup the storage nodes and their devices if they differ from the databag
# RIND_NODE_CONFIG
# <ring> <zone> <storage node IP address>  <device name> <weight>

#storage_nodes = search(:node, "role:storage")
#storage_nodes.each_with_index do |storage_node, zone|
	#execute "make #{storage_node[:ipaddress]}" do
		#cwd '/etc/swift/'
		##user "swift"
		#command "swift-ring-builder /etc/swift/account.builder add z#{zone}-#{storage_node[:ipaddress]}:6002/#{node[:openstack_swift][:device_name]} 100; exit 0"
                #not_if "test -f /etc/swift/account.builder"
#
	#end
	#execute "make #{storage_node[:ipaddress]}" do
		#cwd '/etc/swift/'
		##user "swift"
		#command "swift-ring-builder /etc/swift/container.builder add z#{zone}-#{storage_node[:ipaddress]}:6001/#{node[:openstack_swift][:device_name]} 100; exit 0"
                #not_if "test -f /etc/swift/account.builder"
	#end
	#execute "make #{storage_node[:ipaddress]}" do
		#cwd '/etc/swift/'
		##user "swift"
		#command "swift-ring-builder /etc/swift/object.builder add z#{zone}-#{storage_node[:ipaddress]}:6000/#{node[:openstack_swift][:device_name]} 100; exit 0"
                #not_if "test -f /etc/swift/account.builder"
	#end
#end

# rebalance the rings, if things have changed

%w{account object container}.each do |ringtype|
	execute "rebalance the #{ringtype} ring" do
		cwd '/etc/swift/'
		command "swift-ring-builder /etc/swift/#{ringtype}.builder rebalance"
		not_if "test -f /etc/swift/#{ringtype}.builder"
	end
end


# send the rings to all the nodes, if things have changed
storage_nodes.each_with_index do |storage_node, zone|
	execute "scp rings to #{storage_node[:ipaddress]}" do
		cwd '/etc/swift/'
		#user "swift"
		command "scp /etc/swift/*.gz #{storage_node[:ipaddress]}:/etc/swift/"
		not_if "test -f /etc/swift/account.builder"
	end
end

directory "/etc/swift" do
  recursive true
  owner node[:openstack_swift][:user]
  group node[:openstack_swift][:group]
  mode "0644"
end


#log("data bagerry " + my_conf[ring_common] )
