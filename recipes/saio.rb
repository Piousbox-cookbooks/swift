
#
# Recipe to install SAIO.
#
# From: http://docs.openstack.org/developer/swift/development_saio.html
#
if 'ubuntu' != node['platform']
  raise Exception.new("Only works on Ubuntu 14.04 mon! " + 
                      "You may modify this recipe to accomodate other platforms and versions.")
end

app = data_bag_item('apps', 'saio')

user app['user']
group app['group']

directory "/home/#{app['user']}/bin" do
  recursive true 
end

directory app['deploy_to'] do
  recursive true 
end

app['extra_dirs'].each do |dir|
  directory dir do
    recursive true
  end
end

execute 'apt-get update -y'

# install packages
%w{ curl gcc memcached rsync sqlite3 xfsprogs
  git-core libffi-dev python-setuptools
  python-coverage python-dev python-nose
  python-simplejson python-xattr python-eventlet
  python-greenlet python-pastedeploy
  python-netifaces python-pip python-dnspython
  python-mock
  memcached build-essential emacs git tree
  python-keystoneclient
}.each { |pkg| package pkg }

template "/tmp/loopback_device_as_storage.sh" do
  source "loopback_device_as_storage.sh.erb"
  owner app['user']
  group app['group']
  mode 0755
  variables(:user => app['user'],
            :group => app['group']
            )
end
execute "/tmp/loopback_device_as_storage.sh"

execute "post-device setup" do
  command <<-EOLEOL
#
mkdir -p /var/cache/swift /var/cache/swift2 /var/cache/swift3 /var/cache/swift4
chown #{app['user']}:#{app['group']} /var/cache/swift*
mkdir -p /var/run/swift
chown #{app['user']}:#{app['group']} /var/run/swift
#
EOLEOL
end

execute "git clone #{app['python_swiftclient_repo']}" do
  cwd "#{app['deploy_to']}/../"
  not_if { File.exist?( app['deploy_to'] ) }
end

execute "python setup.py develop" do
  user 'root'
  cwd "#{app['deploy_to']}/../python-swiftclient"
end

##
## ubuntu 12.04 needs this
##
# cd $HOME/python-swiftclient; sudo pip install -r requirements.txt; sudo python setup.py develop; cd -

execute "git clone #{app['repository']}" do
  cwd "#{app['deploy_to']}/../"
  not_if { File.exist?( "#{app['deploy_to']}/../python-swiftclient" ) }
end

##
## Fedora needs this
##
# sudo pip install -U xattr

execute "python setup.py develop && pip install -r test-requirements.txt" do
  user 'root'
  cwd app['deploy_to']
end

execute "post deploy setup" do
  user 'root'
  command <<-EOLEOL
#
cp #{app['deploy_to']}/doc/saio/rsyncd.conf /etc/
sed -i "s/<your-user-name/#{app['user']}/" /etc/rsyncd.conf
sed -i "s/RSYNC_ENABLE=false/RSYNC_ENABLE=true/" /etc/default/rsync
service rsync restart
service memcached start
#
EOLEOL
end

execute "configuring each node" do
  user 'root'
  command <<-EOLEOL
#
cp -r #{app['deploy_to']}/doc/saio/swift /etc/swift
chown -R #{app['user']}:#{app['group']} /etc/swift
find /etc/swift/ -name \*.conf | xargs sudo sed -i "s/<your-user-name>/#{app['user']}/"
#
EOLEOL
end

execute "setting up scripts for running Swift" do
  user 'root'
  cwd "#{app['deploy_to']}/doc"
  command <<-EOLEOL
#
cp -r saio/bin/* /home/#{app['user']}/bin/*
chmod +x /home/#{app['user']}/bin/*
sed -i "s/dev\/sdb1/srv\/swift-disk/" /home/#{app['user']}/bin/resetswift
sed -i "/find \/var\/log\/swift/d" /home/#{app['user']}/bin/resetswift
cp #{app['deploy_to']}/test/sample.conf /etc/swift/test.conf
echo "export SWIFT_TEST_CONFIG_FILE=/etc/swift/test.conf" >> /home/#{app['user']}/.bashrc
echo "export PATH=${PATH}:/home/#{app['user']}/bin" >> /home/#{app['user']}/.bashrc
#
sudo remakerings
# sudo #{app['deploy_to']}/.unittests
sudo startmain
# sudo #{app['deploy_to']}/.functests
# sudo #{app['deploy_to']}/.probetests
#
EOLEOL
end
