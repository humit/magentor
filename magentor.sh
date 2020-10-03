#!/usr/bin/env bash

# References
# Magento Requirements:
# https://devdocs.magento.com/guides/v2.3/install-gde/system-requirements-tech.html
#
# Required PHP Settings
# https://devdocs.magento.com/guides/v2.3/install-gde/prereq/php-settings.html
#
# Magento Performance
# https://medium.com/@vincentteyssier/optimizing-magento2-php-fpm-configuration-parameters-e1da16173e1c
# https://info2.magento.com/rs/magentosoftware/images/MagentoECG-PoweringMagentowithNgnixandPHP-FPM.pdf
#
# Command line installation reference
# https://devdocs.magento.com/guides/v2.3/install-gde/install/cli/install-cli-install.html#instgde-install-cli-magento

VERSION="0.01"
logFile="install.log"

# VARIABLES
phpCliConf="/etc/php/7.3/cli/php.ini "
phpFpmConf="/etc/php/7.3/fpm/php.ini "
phpMemoryLimit="2G"
phpMaxExec="1800"

magentoRepoUser="CHANGEME"
magentoRepoPass="CHANGEME"

magentoTz="America/Los_Angeles"
magentoLang="en_US"
magentoCurr="USD"
magentoOwner="www"
magentoRootPfx="/home/${magentoOwner}"
magentoRootDir=""
magentoDbHost="localhost"
magentoDbName="magento"
magentoDbUser="magento"

# Get public IP of EC2
awsToken=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2> /dev/null)
publicIP=$(curl -H "X-aws-ec2-metadata-token: $awsToken" -v http://169.254.169.254/latest/meta-data/public-ipv4 2> /dev/null)
publicNM=$(curl -H "X-aws-ec2-metadata-token: $awsToken" -v http://169.254.169.254/latest/meta-data/public-hostname 2> /dev/null)

genPass(){
 mkLog "Generating passwords"
 magentoDbPass=$(apg -n1  -m25 -M NCL)
 magentoAdminPass=$(apg -n1 -m25 -M NCL)
 magentoAdminURL=$(apg -n1 -m10 -M NCL)
 mysqlPass=$(apg -n1 -m25 -M NCL)
}

printSummary(){
 echo -e "Public DNS:\t http://${publicNM}"
 echo -e "Admin URL:\t http://${publicNM}/${magentoAdminURL}"
 echo -e "Public IP Address:\t${publicIP}"
 echo -e "Mysql Password:\t${mysqlPass}"
 echo -e "Magento Admin Pass:\t${magentoAdminPass}"
 echo -e "Magento DB Host:\t${magentoDbHost}"
 echo -e "Magento DB User:\t${magentoDbUser}"
 echo -e "Magento DB Pass:\t${magentoDbPass}"
 echo -e "Magento Root Path:\t${magentoRootPath}"
}

mkLog(){
 echo "[$(date +%c)] $@" | tee -a ${logFile}
}

# Error catching function
checkErr(){
 mkLog "An error occured"
}

# Prompt for Magento Root Path
askParams(){

 getDir(){
 if [ -d ${magentoRootPfx}/${magentoRootDir} ] || [ -z ${magentoRootDir} ];then
  echo "path is ${magentoRootPfx}/${magentoRootDir} / dir is ${magentoRootDir}"
  mkLog "The provided directory is already exists, or empty string provided"
  read -p "Magento directory name: ${magentoRootPfx}/[dir_name]: " magentoRootDir
   getDir
 else
      magentoRootPath="${magentoRootPfx}/${magentoRootDir}"
      mkLog "Magento Root Path is set as: ${magentoRootPath}"
 fi
}

 read -p "Admin Name: " magentoAdminName
 read -p "Admin Last Name: " magentoAdminLastName
 read -p "Admin e-mail: " magentoAdminEmail
 read -p "Magento directory name: ${magentoRootPfx}/[dir_name]: " magentoRootDir
 getDir

}

aptInstall(){
sudo debconf-set-selections <<< "postfix postfix/mailname string ${publicNM}"
sudo debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"

sudo add-apt-repository -y ppa:ondrej/php && \
sudo apt update && \
sudo apt upgrade -y && \
sudo apt install -y postfix nginx apg unzip net-tools && \
sudo apt install -y mariadb-server mariadb-client && \
sudo apt install -y php7.3 php7.3-common php7.3-fpm php7.3-dev php7.3-bcmath \
php7.3-ctype php7.3-curl php7.3-dom php7.3-gd \
php7.3-iconv php7.3-intl php7.3-mbstring  \
php7.3-pdo php7.3-mysql php7.3-xml php7.3-simplexml \
php7.3-zip php7.3-soap php7.3-xsl php7.3-opcache \
php7.3-xmlrpc php7.3-phpdbg php7.3-json

# php7.3-mcrypt does not exist and not listed as required.
}

configPhp(){
 # Apply this setting both to cli and fpm
 sudo sed -i -e "s/^\;date\.timezone\ =$/date.timezone\ =\ ${magentoTz/\//\\/}/" \
             -e "s/^memory_limit\ =.*/memory_limit\ =\ ${phpMemoryLimit}/g" \
             -e "s/^max_execution_time\ =.*/max_execution_time\ =\ ${phpMaxExec}/g" \
             -e "s/^zlib.output_compression\ =.*/zlib.output_compression\ =\ On/g" \
             -e "s/^\;opcache.save_comments\ =.*/opcache.save_comments\ =\ 1/" \
             ${phpCliConf} ${phpFpmConf}
}

configNginx(){
 sudo sed -i -e "s/\#\ server_names_hash_bucket_size\ 64\;/server_names_hash_bucket_size\ 128\;/" /etc/nginx/nginx.conf

 sudo bash -c "cat >/etc/nginx/sites-available/${magentoRootDir}" <<EOF
upstream fastcgi_backend {
  server  unix:/run/php/php-fpm.sock;
}

server {
  listen 80;
  server_name ${publicNM} ${magentoRootDir};
  set \$MAGE_ROOT ${magentoRootPath};
  include ${magentoRootPath}/nginx.conf.sample;
}
EOF

sudo ln -s /etc/nginx/sites-available/${magentoRootDir} /etc/nginx/sites-enabled

sudo nginx -t # check syntax
sudo chown -R ${magentoOwner}:${magentoOwner} /var/log/nginx
sudo systemctl restart nginx  # apply changes
}

configSys(){
mkLog "adding magento owner: ${magentoOwner}"
sudo useradd -m -s /bin/bash ${magentoOwner}
mkLog "changing www-data with ${magentoOwner} in config files"
sudo find /etc/nginx -type f -exec sed -i 's/www-data/www/g' {} + && \
sudo find /etc/php -type f -exec sed -i 's/www-data/www/g' {} + && \
sudo systemctl restart php7.3-fpm
}

configMysql(){

# change max_allowed_packet in my.cnf for large product uploads

sudo mysql -u root -p"${mysqlPass}" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${mysqlPass}';" && \
sudo mysql -u root -p"${mysqlPass}" -e "FLUSH PRIVILEGES" && \
mysql -u root -p"${mysqlPass}" -e "UPDATE mysql.user SET Password=PASSWORD('$mysqlPass') WHERE User='root'" && \
mysql -u root -p"${mysqlPass}" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')" && \
mysql -u root -p"${mysqlPass}" -e "DELETE FROM mysql.user WHERE User=''" && \
mysql -u root -p"${mysqlPass}" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'" && \
mysql -u root -p"${mysqlPass}" -e "CREATE DATABASE $magentoDbName" && \
mysql -u root -p"${mysqlPass}" -e "CREATE USER $magentoDbUser IDENTIFIED BY '$magentoDbPass'" && \
mysql -u root -p"${mysqlPass}" -e "GRANT ALL ON ${magentoDbName}.* TO ${magentoDbUser}@${magentoDbHost} IDENTIFIED BY '$magentoDbPass'" && \
mysql -u root -p"${mysqlPass}" -e "FLUSH PRIVILEGES"
}

setupComposer(){
mkLog "Installing composer"
 curl -sS https://getcomposer.org/installer -o composer-setup.php && \
 chmod +x composer-setup.php && \
 sudo php composer-setup.php --install-dir=/bin --filename=composer && \
 sudo su - ${magentoOwner} -c "mkdir -p ~/.composer && echo '{}' > ~/.composer/composer.json" && \
 rm -f composer-setup.php
}

installMagento(){
sudo mkdir -p ${magentoRootPath}
sudo chown -R ${magentoOwner}:${magentoOwner} ${magentoRootPath}
mkLog "sudo su - ${magentoOwner} -c \"composer create-project -vvv --repository-url=https://${magentoRepoUser}:${magentoRepoPass}@repo.magento.com/ magento/project-community-edition ${magentoRootPath}\""
sudo su - ${magentoOwner} -c "composer create-project -vvv --repository-url=https://${magentoRepoUser}:${magentoRepoPass}@repo.magento.com/ magento/project-community-edition ${magentoRootPath}"
cd ${magentoRootPath}
sudo find var generated vendor pub/static pub/media app/etc -type f -exec chmod g+w {} +
sudo find var generated vendor pub/static pub/media app/etc -type d -exec chmod g+ws {} +
sudo chmod u+x ${magentoRootPath}/bin/magento

mkLog "##### MAGENTO SETUP COMMAND #####"
mkLog "sudo su - ${magentoOwner} -c \"${magentoRootPath}/bin/magento setup:install \
--base-url=http://${publicNM}/ \
--db-host=\"${magentoDbHost}\" \
--db-name=\"${magentoDbName}\" \
--db-user=\"${magentoDbUser}\" \
--db-password=\"${magentoDbPass}\" \
--backend-frontname=\"${magentoAdminURL}\" \
--admin-firstname=\"${magentoAdminName}\" \
--admin-lastname=\"${magentoAdminLastName}\" \
--admin-email=\"${magentoAdminEmail}\" \
--admin-user=admin \
--admin-password=\"${magentoAdminPass}\" \
--language=\"${magentoLang}\" \
--currency=\"${magentoCurr}\" \
--timezone=\"${magentoTz}\" \
--use-rewrites=1\""

sudo su - ${magentoOwner} -c "${magentoRootPath}/bin/magento setup:install \
--base-url=http://${publicNM}/ \
--db-host="${magentoDbHost}" \
--db-name="${magentoDbName}" \
--db-user="${magentoDbUser}" \
--db-password="${magentoDbPass}" \
--backend-frontname="${magentoAdminURL}" \
--admin-firstname="${magentoAdminName}" \
--admin-lastname="${magentoAdminLastName}" \
--admin-email="${magentoAdminEmail}" \
--admin-user=admin \
--admin-password="${magentoAdminPass}" \
--language="${magentoLang}" \
--currency="${magentoCurr}" \
--timezone="${magentoTz}" \
--use-rewrites=1" && \
sudo su - ${magentoOwner} -c "${magentoRootPath}/bin/magento deploy:mode:set developer"
}

doUninstall(){
magentoRootDir="magento"
sudo systemctl stop nginx
sudo systemctl stop postfix
sudo systemctl stop php7.3-fpm
sudo apt -y purge nginx postfix
sudo systemctl stop mysql && sudo apt purge -y mariadb-server  mariadb-server-10.3 \
mariadb-server-core-10.3 mariadb-common  mariadb-client-core-10.3 mariadb-client-10.3 mariadb-client && sudo rm -rf /var/lib/mysql/*
sudo userdel -r ${magentoOwner}
sudo rm /etc/nginx/sites-available/${magentoRootDir}
sudo rm /etc/nginx/sites-enabled/${magentoRootDir}
}


doInstall(){
askParams && \
aptInstall && \
genPass && \
configPhp && \
configSys && \
configMysql && \
setupComposer && \
installMagento && \
configNginx
printSummary
}

showHelp(){
 echo
 echo "Magento installer and system configurator v $VERSION"
 echo "Usage: $0 [-i|-u]"
}

if [ $# -eq 0 ];then
 showHelp
 else
  while getopts ":icu" opt;do
   case $opt in
     i) doInstall | tee -a ${logFile}
        ;;
     u) doUninstall
        ;;
     *) showHelp
        ;;
   esac
  done
fi

