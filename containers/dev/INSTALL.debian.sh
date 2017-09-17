#!/bin/bash

# Run: curl -L -s https://raw.githubusercontent.com/r888888888/danbooru/master/INSTALL.debian -o install.sh ; chmod +x install.sh ; ./install.sh

if [[ "$(whoami)" != "root" ]] ; then
  echo "You must run this script as root"
  exit 1
fi

verlte() {
  [ "$1" = "`echo -e "$1\n$2" | sort -V | head -n1`" ]
}

verlt() {
  [ "$1" = "$2" ] && return 1 || verlte $1 $2
}

echo "* DANBOORU INSTALLATION SCRIPT"
echo "*"
echo "* This script will install all the necessary packages to run Danbooru on a   "
echo "* Debian server."
echo
echo -n "* Enter the hostname for this server (ex: danbooru.donmai.us): "
#read HOSTNAME
HOSTNAME=abcdef

if [[ -z "$HOSTNAME" ]] ; then
  echo "* Must enter a hostname"
  exit 1
fi

export RUBY_VERSION=2.3.1
export GITHUB_INSTALL_SCRIPTS=https://raw.githubusercontent.com/r888888888/danbooru/master/script/install

# Install packages
echo "* Installing packages..."
apt-get update
apt-get -y install build-essential automake libssl-dev libxml2-dev libxslt-dev ncurses-dev sudo libreadline-dev flex bison ragel memcached libmemcached-dev git curl libcurl4-openssl-dev imagemagick libmagickcore-dev libmagickwand-dev sendmail-bin sendmail postgresql postgresql-contrib libpq-dev postgresql-server-dev-all nginx ssh coreutils ffmpeg mkvtoolnix

if [ $? -ne 0 ]; then
  echo "* Error installing packages; aborting"
  exit 1
fi

# Create user account
useradd -m danbooru
chsh -s /bin/bash danbooru
usermod -G danbooru,sudo danbooru

# Set up Postgres
export PG_VERSION=`pg_config --version | egrep -o '[0-9]{1,}\.[0-9]{1,}'`
if verlte 9.5 $PG_VERSION ; then
	# only do this on postgres 9.5 and above
	git clone https://github.com/r888888888/test_parser.git /tmp/test_parser
	cd /tmp/test_parser
	make install
fi

# Install rbenv
echo "* Installing rbenv..."
cd /
sudo -u danbooru git clone git://github.com/sstephenson/rbenv.git ~danbooru/.rbenv
sudo -u danbooru touch ~danbooru/.bash_profile
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~danbooru/.bash_profile
echo 'eval "$(rbenv init -)"' >> ~danbooru/.bash_profile
sudo -u danbooru mkdir -p ~danbooru/.rbenv/plugins
sudo -u danbooru git clone git://github.com/sstephenson/ruby-build.git ~danbooru/.rbenv/plugins/ruby-build
sudo -u danbooru bash -l -c "rbenv install $RUBY_VERSION"
sudo -u danbooru bash -l -c "rbenv global $RUBY_VERSION"

# Generate secret token and secret key
echo "* Generating secret keys..."
sudo -u danbooru mkdir -p ~danbooru/.danbooru/
sudo -u danbooru sh -c 'openssl rand -hex 32 > ~danbooru/.danbooru/secret_token'
sudo -u danbooru sh -c 'openssl rand -hex 32 > ~danbooru/.danbooru/session_secret_key'
chmod 600 ~danbooru/.danbooru/*

# Install gems
echo "* Installing gems..."
sudo -u danbooru bash -l -c 'gem install --no-ri --no-rdoc bundler'

echo "* Install configuration scripts..."

# Update PostgreSQL
curl -L -s $GITHUB_INSTALL_SCRIPTS/postgresql_hba_conf -o /etc/postgresql/$PG_VERSION/main/pg_hba.conf
/etc/init.d/postgresql restart
sudo -u postgres createuser -s danbooru
sudo -u danbooru createdb danbooru2

# Setup nginx
curl -L -s $GITHUB_INSTALL_SCRIPTS/nginx.danbooru.conf -o /etc/nginx/sites-enabled/danbooru.conf
sed -i -e "s/__hostname__/$HOSTNAME/g" /etc/nginx/sites-enabled/danbooru.conf
/etc/init.d/nginx restart

# Setup logrotate
curl -L -s $GITHUB_INSTALL_SCRIPTS/danbooru_logrotate_conf -o /etc/logrotate.d/danbooru.conf

# Setup danbooru account
echo "* Enter a new password for the danbooru account"
passwd danbooru

echo "* Setting up SSH keys for the danbooru account"
sudo -u danbooru ssh-keygen

mkdir -p /var/www/danbooru2/shared/config
mkdir -p /var/www/danbooru2/shared/data
mkdir -p /var/www/danbooru2/shared/data/preview
mkdir -p /var/www/danbooru2/shared/data/sample
chown -R danbooru:danbooru /var/www/danbooru2
curl -L -s $GITHUB_INSTALL_SCRIPTS/database.yml.templ -o /var/www/danbooru2/shared/config/database.yml
curl -L -s $GITHUB_INSTALL_SCRIPTS/danbooru_local_config.rb.templ -o /var/www/danbooru2/shared/config/danbooru_local_config.rb

echo "* Almost done! You are now ready to deploy Danbooru onto this server."
echo "* Log into Github and fork https://github.com/r888888888/danbooru into"
echo "* your own repository. Clone your fork onto your local development"
echo "* machine and modify the following files:"
echo "*"
echo "*   config/deploy.rb (github repo url)"
echo "*   config/deploy/production.rb (servers and users)"
echo "*   config/unicorn/production.rb (users)"
echo "*   config/application.rb (time zone)"
echo "*"
echo "* On the remote server you will want to modify this file:"
echo "*"
echo "*   /var/www/danbooru2/shared/config/danbooru_local_config.rb"
echo "*"
read -p "Press [enter] to continue..."
echo "* Commit your changes and push them to your fork. You are now ready to"
echo "* deploy with the following command:"
echo "*"
echo "*   bundle exec capistrano production deploy"
echo "*"
echo "* You can also run a server locally without having to deal with deploys"
echo "* by running the following command:"
echo "*"
echo "*   bundle install"
echo "*   RAILS_ENV=production bundle exec rake db:create db:migrate"
echo "*   RAILS_ENV=production bundle exec rails server"
echo "*"
echo "* This will start a web process running on port 3000 that you can"
echo "* connect to. This is useful for development and testing purposes."
echo "* If something breaks post about it on the Danbooru Github. Good luck!"
