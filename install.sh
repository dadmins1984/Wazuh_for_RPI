#!/bin/sh

#change it on the your username
Systemuser="pi"

apt --fix-broken install -y 
check_command() {
    if [ $? -ne 0 ]; then
        echo "Error: $1 script stopped"
        exit 1
    fi
}

sudo apt update && sudo apt upgrade -y
check_command "Package update"

sudo apt-get install -y ufw
check_command "Install UFW"
    
############optional###############
#ufw allow from [IP] to any port 22
ufw allow 22
check_command "UFW adding Allow port: 22"

ufw default deny incoming
check_command "UFW Deny any incoming traffic"

ufw default allow outgoing
check_command "UFW Allow any outgoing traffic"

ufw --force enable
check_command "UFW enable - hardening"
    
sudo apt --fix-broken install -y
check_command "Repairing damaged packages"

sudo apt install apt-transport-https zip unzip lsb-release curl gnupg -y
check_command "Dependency installation"

curl -s https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/elasticsearch.gpg --import && chmod 644 /usr/share/keyrings/elasticsearch.gpg
check_command "Adding Elasticsearch key"
    
echo "deb [signed-by=/usr/share/keyrings/elasticsearch.gpg] https://artifacts.elastic.co/packages/7.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-7.x.list
check_command "Adding Elasticsearch repository"

sudo apt update
check_command "Updating repositories after adding Elasticsearch"

sudo apt install elasticsearch=7.17.13 -y
check_command "Installing Elasticsearch"

curl -so /etc/elasticsearch/elasticsearch.yml https://packages.wazuh.com/4.5/tpl/elastic-basic/elasticsearch_all_in_one.yml
check_command "Downloading Elasticsearch configuration"
    
curl -so /usr/share/elasticsearch/instances.yml https://packages.wazuh.com/4.5/tpl/elastic-basic/instances_aio.yml
check_command "Downloading the instances.yml file for Elasticsearch"

cat << 'EOF' > /home/$Systemuser/instances.yml
instances:
  - name: "elasticsearch"
    ip: ["127.0.0.1"]
EOF
check_command "Creating the instances.yml file"

yes | /usr/share/elasticsearch/bin/elasticsearch-certutil cert ca --pem --in /home/$Systemuser/instances.yml --keep-ca-key --out /home/$Systemuser/certs.zip
check_command "Generating Elasticsearch Certificates"

unzip /home/$Systemuser/certs.zip -d /home/$Systemuser/certs
check_command "Unpacking certificates"

sudo mkdir -p /etc/elasticsearch/certs/ca
sudo cp -R /home/$Systemuser/certs/ca/ /home/$Systemuser/certs/elasticsearch/* /etc/elasticsearch/certs/
sudo chown -R elasticsearch: /etc/elasticsearch/certs
sudo chmod -R 500 /etc/elasticsearch/certs
sudo chmod 400 /etc/elasticsearch/certs/ca/ca.* /etc/elasticsearch/certs/elasticsearch.*
check_command "Elasticsearch Certificate Configuration"

rm -rf /home/$Systemuser/certs/ /home/$Systemuser/certs.zip
check_command "Deleting Temporary Certificate Files"

sudo systemctl daemon-reload
check_command "Reload system daemons"
    
sudo systemctl enable elasticsearch
check_command "Enabling Elasticsearch in autostart"

sudo systemctl start elasticsearch
check_command "Starting Elasticsearch"

yes | /usr/share/elasticsearch/bin/elasticsearch-setup-passwords auto > /home/$Systemuser/pass.txt 2>&1
check_command "Generating Elasticsearch Passwords"

password=$(grep "PASSWORD elastic" /home/$Systemuser/pass.txt | awk -F ' = ' '{print $2}')
    if [ -z "$password" ]; then
        echo "Error: Failed to get Elasticsearch password."
        exit 1
    fi

curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && chmod 644 /usr/share/keyrings/wazuh.gpg
check_command "Adding the Wazuh key"
    
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | sudo tee -a /etc/apt/sources.list.d/wazuh.list
check_command "Added Wazuh repository"

sudo apt update
check_command "Updating repositories after adding Wazuh"

yes | sudo apt install wazuh-manager=4.5.4-1 -y
check_command "Installing Wazuh Manager"

sudo systemctl daemon-reload
check_command "Reload daemons after installing Wazuh Manager"

sudo systemctl enable wazuh-manager
check_command "Enabling Wazuh Manager in autostart"

sudo systemctl start wazuh-manager
check_command "Starting Wazuh Manager"

sudo apt install filebeat=7.17.13 -y
check_command "Filebeat installation"

curl -so /etc/filebeat/filebeat.yml https://packages.wazuh.com/4.5/tpl/elastic-basic/filebeat_all_in_one.yml
check_command "Download Filebeat configuration"

curl -so /etc/filebeat/wazuh-template.json https://raw.githubusercontent.com/wazuh/wazuh/v4.5.4/extensions/elasticsearch/7.x/wazuh-template.json
check_command "Download Filebeat template"

sudo chmod go+r /etc/filebeat/wazuh-template.json
check_command "Granting permissions to the Filebeat template"

curl -s https://packages.wazuh.com/4.x/filebeat/wazuh-filebeat-0.2.tar.gz | sudo tar -xvz -C /usr/share/filebeat/module
check_command "Installing the Wazuh module for Filebeat"

sudo sed -i "s/output\.elasticsearch\.password: .*/output.elasticsearch.password: $password/" /etc/filebeat/filebeat.yml
check_command "Elasticsearch Password Configuration for Filebeat"

sudo cp -r /etc/elasticsearch/certs/ca/ /etc/filebeat/certs/
sudo cp /etc/elasticsearch/certs/elasticsearch.crt /etc/filebeat/certs/filebeat.crt
sudo cp /etc/elasticsearch/certs/elasticsearch.key /etc/filebeat/certs/filebeat.key
check_command "Copying certificates to Filebeat"

sudo systemctl daemon-reload
check_command "Reload daemons after Filebeat installation"

sudo systemctl enable filebeat
check_command "Enabling Filebeat in autostart"

sudo systemctl start filebeat
check_command "Starting Filebeat"

sudo apt install kibana=7.17.13 -y
check_command "Kibana installation"

sudo mkdir -p /etc/kibana/certs/ca
sudo cp -R /etc/elasticsearch/certs/ca/ /etc/kibana/certs/
sudo cp /etc/elasticsearch/certs/elasticsearch.key /etc/kibana/certs/kibana.key
sudo cp /etc/elasticsearch/certs/elasticsearch.crt /etc/kibana/certs/kibana.crt
sudo chown -R kibana:kibana /etc/kibana/
sudo chmod -R 500 /etc/kibana/certs
sudo chmod 440 /etc/kibana/certs/ca/ca.* /etc/kibana/certs/kibana.*
check_command "Configuring certificates for Kibana"

curl -so /etc/kibana/kibana.yml https://packages.wazuh.com/4.5/tpl/elastic-basic/kibana_all_in_one.yml
check_command "Downloading Kibana configuration"

sudo sed -i "s/elasticsearch\.password: .*/elasticsearch.password: $password/" /etc/kibana/kibana.yml
check_command "Elasticsearch Password Configuration for Kibana"

sudo mkdir /usr/share/kibana/data
check_command "Folder configuration for Kibana"

sudo chown -R kibana:kibana /usr/share/kibana
check_command "Assigning folder permissions for Kibana"
cd /usr/share/kibana

sudo -u kibana /usr/share/kibana/bin/kibana-plugin install https://packages.wazuh.com/4.x/ui/kibana/wazuh_kibana-4.5.4_7.17.13-1.zip
check_command "Iwazuh plugin installation for kibana"

setcap 'cap_net_bind_service=+ep' /usr/share/kibana/node/bin/node
check_command "Linking kibana to 443"

sudo systemctl daemon-reload
check_command "Reload daemons after installing Kibana"

sudo systemctl enable kibana
check_command "Enabling Kibana in autostart"

sudo systemctl start kibana
check_command "Starting Kibana"

ufw allow 1514
check_command "UFW adding Allow port: 1514"

ufw allow 1515
check_command "UFW adding Allow port: 1515"

ufw allow 1516
check_command "UFW adding Allow port: 1516"

ufw allow 514
check_command "UFW adding Allow port: 514"

ufw allow 55000
check_command "UFW adding Allow port: 55000"

ufw allow 9200
check_command "UFW adding Allow port: 9200"

ufw allow 9300-9400
check_command "UFW adding Allow ports: 9300-9400"

ufw allow 443
check_command "UFW adding Allow port: 443"

sudo ufw enable
check_command "UFW activation"

sed -i "s/^deb/#deb/" /etc/apt/sources.list.d/wazuh.list
sed -i "s/^deb/#deb/" /etc/apt/sources.list.d/elastic-7.x.list
check_command "Disabling extra repositories"

apt-get update
check_command "Updating repositories"

echo "Installation completed successfully!"
echo "************************************"
echo "User: elastic"
echo "Password: $password"
echo "************************************"
