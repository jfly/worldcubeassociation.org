require 'shellwords'
require 'securerandom'

include_recipe "wca::base"
include_recipe "nodejs"

secrets = WcaHelper.get_secrets(self)
username, repo_root = WcaHelper.get_username_and_repo_root(self)
if username == "cubing"
  user_lockfile = '/tmp/cubing-user-initialized'
  user username do
    supports :manage_home => true
    home "/home/#{username}"
    shell '/bin/bash'
    password do
      cmd = ["openssl", "passwd", "-1", secrets['cubing_password']].shelljoin
      `#{cmd}`.strip
    end
    not_if { ::File.exists?(user_lockfile) }
  end

  # Trick to run code immediately and last copied from:
  #  https://gist.github.com/nvwls/7672039
  ruby_block 'last' do
    block do
      puts "#"*80
      puts "# Created user #{username} with password #{secrets['cubing_password']}"
      puts "#"*80
    end
    not_if { ::File.exists?(user_lockfile) }
  end
  ruby_block 'notify' do
    block do
      true
    end
    notifies :run, 'ruby_block[last]', :delayed
    not_if { ::File.exists?(user_lockfile) }
  end

  file user_lockfile do
    action :create_if_missing
  end

  ssh_known_hosts_entry 'github.com'
  chef_env_to_branch = {
    "development" => "master",
    "staging" => "master",
    "production" => "production",
  }
  branch = chef_env_to_branch[node.chef_environment]
  git repo_root do
    repository "git@github.com:cubing/worldcubeassociation.org.git"
    revision branch
    # See http://lists.opscode.com/sympa/arc/chef/2015-03/msg00308.html
    # for the reason for checkout_branch and "enable_checkout false"
    checkout_branch branch
    enable_checkout false
    action :sync
    enable_submodules true

    # Unfortunately, setting the user and group breaks ssh agent forwarding.
    # Instead, let root user do the git checkout, and then chown appropriately.
    #user username
    #group username
    notifies :run, "execute[fix-permissions]", :immediately
  end
  execute "fix-permissions" do
    command "chown -R #{username}:#{username} #{repo_root}"
    user "root"
    action :nothing
  end
end
rails_root = "#{repo_root}/WcaOnRails"


#### Mysql
mysql_service 'default' do
  version '5.5'
  initial_root_password secrets['mysql_password']
  # Force default socket to make rails happy
  socket "/var/run/mysqld/mysqld.sock"
  action [:create, :start]
end
mysql_config 'default' do
  source 'mysql-wca.cnf.erb'
  notifies :restart, 'mysql_service[default]'
  action :create
end
template "/etc/my.cnf" do
  source "my.cnf.erb"
  mode 0644
  owner 'root'
  group 'root'
  variables({
    secrets: secrets
  })
end
db_dump_filename = "#{repo_root}/secrets/worldcubeassociation.org_alldbs.tar.gz"
execute "#{repo_root}/scripts/db.sh import #{db_dump_filename}"


#### Ruby and Rails
# Install native dependencies for gems
package 'libghc-zlib-dev'
package 'libsqlite3-dev'
package 'g++'
package 'libmysqlclient-dev'

node.default['brightbox-ruby']['version'] = "2.2"
include_recipe "brightbox-ruby"
gem_package "rails" do
  version "4.2.1"
end
chef_env_to_rails_env = {
  "development" => "development",
  "staging" => "production",
  "production" => "production",
}
rails_env = chef_env_to_rails_env[node.chef_environment]


#### Nginx
# Unfortunately, we have to compile nginx from source to get the auth request module
# See: https://bugs.launchpad.net/ubuntu/+source/nginx/+bug/1323387

# Nginx dependencies copied from http://www.rackspace.com/knowledge_center/article/ubuntu-and-debian-installing-nginx-from-source
package 'libc6'
package 'libpcre3'
package 'libssl0.9.8'
package 'zlib1g'
package 'lsb-base'
# http://stackoverflow.com/a/14046228
package 'libpcre3-dev'
# http://serverfault.com/a/416573
package 'libssl-dev'

bash "build nginx" do
  code <<-EOH
    set -e # exit on error
    cd /tmp
    wget http://nginx.org/download/nginx-1.8.0.tar.gz
    tar xvf nginx-1.8.0.tar.gz
    cd nginx-1.8.0
    ./configure --sbin-path=/usr/local/sbin --with-http_ssl_module --with-http_auth_request_module --with-http_gzip_static_module --conf-path=/etc/nginx/nginx.conf --error-log-path=/var/log/nginx/error.log --http-log-path=/var/log/nginx/access.log
    make
    sudo make install
    EOH

  # Don't build nginx if we've already built it.
  not_if { ::File.exists?('/usr/local/sbin/nginx') }
end
template "/etc/nginx/fcgi.conf" do
  source "fcgi.conf.erb"
  variables({
    username: username,
  })
  notifies :run, 'execute[reload-nginx]', :delayed
end
template "/etc/nginx/nginx.conf" do
  source "nginx.conf.erb"
  mode 0644
  owner 'root'
  group 'root'
  variables({
    username: username,
  })
  notifies :run, 'execute[reload-nginx]', :delayed
end
directory "/etc/nginx/conf.d" do
  owner 'root'
  group 'root'
end

server_name = { "production" => "www.worldcubeassociation.org", "staging" => "staging.worldcubeassociation.org", "development" => "" }[node.chef_environment]
# Use HTTPS in non development mode
https = node.chef_environment != "development"
template "/etc/nginx/conf.d/worldcubeassociation.org.conf" do
  source "worldcubeassociation.org.conf.erb"
  mode 0644
  owner 'root'
  group 'root'
  variables({
    username: username,
    rails_root: rails_root,
    repo_root: repo_root,
    rails_env: rails_env,
    https: https,
    server_name: server_name,
  })
  notifies :run, 'execute[reload-nginx]', :delayed
end
template "/etc/nginx/wca_https.conf" do
  source "wca_https.conf.erb"
  mode 0644
  owner 'root'
  group 'root'
  variables({
    username: username,
    rails_root: rails_root,
    repo_root: repo_root,
    rails_env: rails_env,
    https: https,
    server_name: server_name,
  })
  notifies :run, 'execute[reload-nginx]', :delayed
end
# Start nginx if it's not already running.
execute "nginx" do
  not_if "ps -efw | grep nginx.*master"
end
execute "reload-nginx" do
  command "nginx -s reload || nginx"
  action :nothing
end


#### Rails secrets
template "#{rails_root}/.env.production" do
  source "env.production"
  mode 0644
  owner username
  group username
  variables({
    secrets: secrets,
  })
end

#### Legacy PHP results system
PHP_MEMORY_LIMIT = '512M'
PHP_IDLE_TIMEOUT_SECONDS = 120
package 'php5-cli'
include_recipe 'php-fpm::install'
php_fpm_pool "www" do
  listen "/var/run/php5-fpm.#{username}.sock"
  user username
  group username
  process_manager "dynamic"
  max_children 9
  min_spare_servers 2
  max_spare_servers 4
  max_requests 200
  php_options 'php_admin_flag[log_errors]' => 'on', 'php_admin_value[memory_limit]' => PHP_MEMORY_LIMIT
end
execute "sudo sed -i 's/memory_limit = .*/memory_limit = #{PHP_MEMORY_LIMIT}/g' /etc/php5/fpm/php.ini" do
  not_if "grep 'memory_limit = #{PHP_MEMORY_LIMIT}' /etc/php5/fpm/php.ini"
end
execute "sudo sed -i 's/max_execution_time = .*/max_execution_time = #{PHP_IDLE_TIMEOUT_SECONDS}/g' /etc/php5/fpm/php.ini" do
  not_if "grep 'max_execution_time = #{PHP_IDLE_TIMEOUT_SECONDS}' /etc/php5/fpm/php.ini"
end
# Install pear mail
# http://www.markstechstuff.com/2009/04/installing-pear-mail-for-php-on-ubuntu.html
package "php-pear"
execute "pear install mail Net_SMTP Auth_SASL mail_mime"
# Install mysqli for php. See:
#  http://stackoverflow.com/a/22525205
package "php5-mysqlnd"
template "#{repo_root}/webroot/results/includes/_config.php" do
  source "results_config.php.erb"
  mode 0644
  owner username
  group username
  variables({
    secrets: secrets,
  })
end


#### Screen
template "/home/#{username}/.bash_profile" do
  source "bash_profile.erb"
  mode 0644
  owner username
  group username
end
template "/home/#{username}/.bashrc" do
  source "bashrc.erb"
  mode 0644
  owner username
  group username
end
template "/home/#{username}/wca.screenrc" do
  source "wca.screenrc.erb"
  mode 0644
  owner username
  group username
  variables({
    rails_root: rails_root,
    rails_env: rails_env,
  })
end
template "/home/#{username}/startall" do
  source "startall.erb"
  mode 0755
  owner username
  group username
end
# We "sudo su ..." because simply specifying "user ..." doesn't invoke a login shell,
# which makes for a very screwy screen (we're logged in as username, but HOME
# is /home/root, for instance).
execute "sudo su #{username} -c '~/startall'" do
  user username
  not_if "screen -S wca -Q select", user: username
end
# Start screen at boot by creating our own /etc/init.d/rc.local
# Hopefully no one else needs to touch this file... there has *got* to be a
# more portable way of doing this.
template "/etc/rc.local" do
  source "rc.local.erb"
  mode 0755
  owner 'root'
  group 'root'
  variables({
    username: username,
  })
end
