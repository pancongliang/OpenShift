
#!/bin/bash
#######################################################
echo ====== Disable and check firewalld ======

# disable firewalld
systemctl disable firewalld
systemctl stop firewalld

# Wait for a short moment for httpd to start
sleep 10

# Check if a service is disabled
check_service_disabled() {
    service_name=$1
    if systemctl is-enabled "$service_name" | grep -q "disabled"; then
        return 0
    else
        return 1
    fi
}

# Check if a service is stopped
check_service_stopped() {
    service_name=$1
    if systemctl is-active "$service_name" | grep -q "inactive"; then
        return 0
    else
        return 1
    fi
}

# Display status message
display_status_message() {
    service_name=$1
    if check_service_disabled "$service_name" && check_service_stopped "$service_name"; then
        echo "$service_name service is successfully disabled and stopped."
    elif ! check_service_disabled "$service_name"; then
        echo "Error: $service_name service is not disabled."
    elif ! check_service_stopped "$service_name"; then
        echo "Error: $service_name service is not stopped."
    else
        echo "Error: Unable to determine status of $service_name service."
    fi
}

# Check and display status for specific services
display_status_message "firewalld"

#######################################################



echo ====== Disable and check SeLinux ======
# Get current SELinux status
SELINUX=$(getenforce)
echo "$SELINUX"

# Check if SELinux is enforcing and update config if needed
if [ "$SELINUX" = "Enforcing" ]; then
  sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
fi

# Temporarily set SELinux to permissive
setenforce 0 &>/dev/null

# Check current SELinux status (temporary)
current_status=$(getenforce)
echo "Current SELinux status (temporary): $current_status"

# Check permanent SELinux status
config_file_status=$(grep -E "^SELINUX=" /etc/selinux/config | awk -F= '{print $2}')
echo "Permanent SELinux status: $config_file_status"

# Check if both temporary and permanent statuses are not permissive or disabled
if [ "$current_status" != "Permissive" -a "$current_status" != "Disabled" ] || \
   [ "$config_file_status" != "permissive" -a "$config_file_status" != "disabled" ]; then
    echo "Error: SELinux should be set to 'permissive' or 'disabled'."
fi

#######################################################



echo ====== Install infrastructure rpm ======
# Install infrastructure rpm
packages=("wget" "net-tools" "podman" "bind-utils" "bind" "haproxy" "git" "bash-completion" "jq" "nfs-utils" "httpd" "httpd-tools" "skopeo" "httpd-manual")
yum install -y vim &>/dev/null
yum install -y "${packages[@]}" &>/dev/null

# Check if a package is installed
check_package_installed() {
    package_name=$1
    if rpm -q "$package_name" &>/dev/null; then
        echo "$package_name is installed successfully."
    else
        echo "Error: $package_name installation failed."
    fi
}

# Check and display package installation status
all_packages_installed=true
for package in "${packages[@]}"; do
    check_package_installed "$package" || all_packages_installed=false
done

if $all_packages_installed; then
    echo "All packages are installed successfully."
fi

#######################################################



echo ====== Install openshift tool ======
# Install openshift tool
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OCP_RELEASE/openshift-install-linux.tar.gz
tar xvf openshift-install-linux.tar.gz -C /usr/local/bin/ && rm -rf openshift-install-linux.tar.gz

wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz
tar xvf openshift-client-linux.tar.gz -C /usr/local/bin/ && rm -rf /usr/local/bin/README.md && rm -rf openshift-client-linux.tar.gz

curl -O https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz
tar -xvf oc-mirror.tar.gz -C /usr/local/bin/ && chmod a+x /usr/local/bin/oc-mirror && rm -rf oc-mirror.tar.gz

wegt https://mirror.openshift.com/pub/openshift-v4/clients/butane/latest/butane
chmod a+x butane && mv butane /usr/local/bin/

# Check if a command is available
check_command() {
    if command -v "$1" &>/dev/null; then
        help_output=$("$1" --help | grep -q "help")
        if [[ $? -eq 0 ]]; then
            echo "$1 command is installed successfully."
        else
            echo "$1 command installation failed."
        fi
    else
        echo "$1 command installation failed."
        return 1
    fi
}

# List of commands to check
commands=("openshift-install" "oc" "oc-mirror" "butane")

# Check availability of commands and their help output
for cmd in "${commands[@]}"; do
    check_command "$cmd"
done

#######################################################



echo ====== Setup and check httpd services ======

# Update httpd listen port
update_httpd_listen_port() {
    listen_port=$(grep -v "#" /etc/httpd/conf/httpd.conf | grep -i 'Listen' | awk '{print $2}')
    if [ "$listen_port" != "8080" ]; then
        sed -i 's/^Listen .*/Listen 8080/' /etc/httpd/conf/httpd.conf
        systemctl restart httpd
        echo "Apache HTTP Server's listen port has been changed to 8080."
    fi
}

# Create virtual host configuration
create_virtual_host_config() {
    cat << EOF > /etc/httpd/conf.d/base.conf
<VirtualHost *:8080>
   ServerName $BASTION_HOSTNAME
   DocumentRoot $HTTPD_PATH
</VirtualHost>
EOF
}

# Check if virtual host configuration is valid
check_virtual_host_configuration() {
    expected_server_name="$BASTION_HOSTNAME"
    expected_document_root="$HTTPD_PATH"
    virtual_host_config="/etc/httpd/conf.d/base.conf"
    if grep -q "ServerName $expected_server_name" "$virtual_host_config" && \
       grep -q "DocumentRoot $expected_document_root" "$virtual_host_config"; then
        echo "Virtual host configuration is valid."
    else
        echo "Error: Virtual host configuration is not valid."
    fi
}

# Call the function to update listen port
update_httpd_listen_port

# Create virtual host configuration
create_virtual_host_config

# Check virtual host configuration
check_virtual_host_configuration

# Enable and start HAProxy service
systemctl enable httpd
systemctl start httpd
sleep 5

# Check if a service is enabled and running
check_service() {
    service_name=$1

    if systemctl is-enabled "$service_name" &>/dev/null; then
        echo "$service_name service is enabled."
    else
        echo "Error: $service_name service is not enabled."
    fi

    if systemctl is-active "$service_name" &>/dev/null; then
        echo "$service_name service is running."
    else
        echo "Error: $service_name service is not running."
    fi
}

# List of services to check
services=("httpd")

# Check status of all services
for service in "${services[@]}"; do
    check_service "$service"
done

#######################################################



echo ====== Setup nfs services ======
# Create directories
mkdir -p $NFS_DIR/$IMAGE_REGISTRY_PV

# Add nfsnobody user if not exists
if id "nfsnobody" &>/dev/null; then
    echo "nfsnobody user exists."
else
    useradd nfsnobody
    echo "nfsnobody user added."
fi

# Change ownership and permissions
chown -R nfsnobody.nfsnobody $NFS_DIR
chmod -R 777 $NFS_DIR

# Add NFS export configuration
export_config_line="$NFS_DIR    (rw,sync,no_wdelay,no_root_squash,insecure,fsid=0)"
if grep -q "$export_config_line" "/etc/exports"; then
    echo "NFS export configuration already exists."
else
    echo "$export_config_line" >> "/etc/exports"
    echo "NFS export configuration added."
fi

# Enable and start nfs-server service
systemctl enable nfs-server
systemctl restart nfs-server

# Check if a service is enabled and running
check_service() {
    service_name=$1

    if systemctl is-enabled "$service_name" &>/dev/null; then
        echo "$service_name service is enabled."
    else
        echo "Error: $service_name service is not enabled."
    fi

    if systemctl is-active "$service_name" &>/dev/null; then
        echo "$service_name service is running."
    else
        echo "Error: $service_name service is not running."
    fi
}

# List of services to check
services=("nfs-server")

# Check status of all services
for service in "${services[@]}"; do
    check_service "$service"
done



#######################################################
#!/bin/bash
echo ====== Setup named services ======
# Setup named services configuration
cat << EOF > /etc/named.conf
options {
        listen-on port 53 { any; };
        listen-on-v6 port 53 { ::1; };
        directory       "/var/named";
        dump-file       "/var/named/data/cache_dump.db";
        statistics-file "/var/named/data/named_stats.txt";
        memstatistics-file "/var/named/data/named_mem_stats.txt";
        secroots-file   "/var/named/data/named.secroots";
        recursing-file  "/var/named/data/named.recursing";
        allow-query     { any; };
        forwarders      { $DNS_FORWARDER_IP; };

        /* 
         - If you are building an AUTHORITATIVE DNS server, do NOT enable recursion.
         - If you are building a RECURSIVE (caching) DNS server, you need to enable 
           recursion. 
         - If your recursive DNS server has a public IP address, you MUST enable access 
           control to limit queries to your legitimate users. Failing to do so will
           cause your server to become part of large scale DNS amplification 
           attacks. Implementing BCP38 within your network would greatly
           reduce such attack surface 
        */
        recursion yes;
        # mod
        # allow-query-cache { none; };
        #recursion no;
        # mod

        dnssec-enable yes;
        dnssec-validation yes;

        managed-keys-directory "/var/named/dynamic";

        pid-file "/run/named/named.pid";
        session-keyfile "/run/named/session.key";

        /* https://fedoraproject.org/wiki/Changes/CryptoPolicy */
        //include "/etc/crypto-policies/back-ends/bind.config";
};

zone "$BASE_DOMAIN" IN {
        type master;
        file "$BASE_DOMAIN.zone";
        allow-query { any; };
};

zone "$REVERSE_ZONE" IN {
        type master;
        file "$REVERSE_ZONE_FILE_NAME";
        allow-query { any; };
};

logging {
        channel default_debug {
                file "data/named.run";
                severity dynamic;
        };
};

zone "." IN {
        type hint;
        file "named.ca";
};

include "/etc/named.rfc1912.zones";
//include "/etc/named.root.key";
EOF
echo "Named service configuration is completed."

# Create forward zone file
cat << EOF >  /var/named/$BASE_DOMAIN.zone
\$TTL 1W
@       IN      SOA     ns1.$BASE_DOMAIN.        root (
                        201907070      ; serial
                        3H              ; refresh (3 hours)
                        30M             ; retry (30 minutes)
                        2W              ; expiry (2 weeks)
                        1W )            ; minimum (1 week)
        IN      NS      ns1.$BASE_DOMAIN.
;
;
ns1     IN      A       $BASTION_IP
;
helper  IN      A       $BASTION_IP
helper.ocp4     IN      A       $BASTION_IP
;
; The api identifies the IP of your load balancer.
api.$CLUSTER_NAME.$BASE_DOMAIN.                            IN      A       $API_IP
api-int.$CLUSTER_NAME.$BASE_DOMAIN.                        IN      A       $API_INT_IP
;
; The wildcard also identifies the load balancer.
*.apps.$CLUSTER_NAME.$BASE_DOMAIN.                         IN      A       $APPS_IP
;
; Create entries for the master hosts.
$MASTER01_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN.             IN      A       $MASTER01_IP
$MASTER02_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN.             IN      A       $MASTER02_IP
$MASTER03_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN.             IN      A       $MASTER03_IP
;
; Create entries for the worker hosts.
$WORKER01_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN.             IN      A       $WORKER01_IP
$WORKER02_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN.             IN      A       $WORKER02_IP
;
; Create an entry for the bootstrap host.
$BOOTSTRAP_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN.            IN      A       $BOOTSTRAP_IP
;
; Create entries for the mirror registry hosts.
$REGISTRY_HOSTNAME.$BASE_DOMAIN.                           IN      A       $REGISTRY_IP
EOF
echo "Forward zone file created."

# Create reverse zone file
cat << EOF >  /var/named/$REVERSE_ZONE_FILE_NAME
\$TTL 1W
@       IN      SOA     ns1.$BASE_DOMAIN.        root (
                        2019070700      ; serial
                        3H              ; refresh (3 hours)
                        30M             ; retry (30 minutes)
                        2W              ; expiry (2 weeks)
                        1W )            ; minimum (1 week)
        IN      NS      ns1.$BASE_DOMAIN.
;
; The syntax is "last octet" and the host must have an FQDN
; with a trailing dot.
;
; The api identifies the IP of your load balancer.
$API_REVERSE_IP                IN      PTR     api.$CLUSTER_NAME.$BASE_DOMAIN.
$API_INT_REVERSE_IP            IN      PTR     api-int.$CLUSTER_NAME.$BASE_DOMAIN.
;
; Create entries for the master hosts.
$MASTER01_REVERSE_IP           IN      PTR     $MASTER01_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN.
$MASTER02_REVERSE_IP           IN      PTR     $MASTER02_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN.
$MASTER03_REVERSE_IP           IN      PTR     $MASTER03_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN.
;
; Create entries for the worker hosts.
$WORKER01_REVERSE_IP           IN      PTR     $WORKER01_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN.
$WORKER02_REVERSE_IP           IN      PTR     $WORKER02_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN.
$WORKER02_REVERSE_IP           IN      PTR     $WORKER02_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN.
;
; Create an entry for the bootstrap host.
$BOOTSTRAP_REVERSE_IP          IN      PTR     $BOOTSTRAP_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN.
EOF
echo "Reverse zone file created."

# Check if the DNS server is already configured in resolv.conf
if ! grep -q "nameserver $DNS_SERVER" /etc/resolv.conf; then
    # Add the DNS server configuration
    echo "nameserver $DNS_SERVER" >> /etc/resolv.conf
    echo "Added DNS server configuration to /etc/resolv.conf."
else
    echo "DNS server configuration already exists in /etc/resolv.conf."
fi

# Change ownership
chown named. /var/named/*.zone

# Check named configuration file
if named-checkconf &>/dev/null; then
    echo "Named configuration is valid."
else
    echo "Error: Named configuration is invalid."
fi

# Check forward zone file
if named-checkzone $BASE_DOMAIN /var/named/$BASE_DOMAIN.zone &>/dev/null; then
    echo "Forward zone file is valid."
else
    echo "Error: Forward zone file is invalid."
fi

# Check reverse zone file
if named-checkzone $REVERSE_ZONE_FILE_NAME /var/named/$REVERSE_ZONE_FILE_NAME &>/dev/null; then
    echo "Reverse zone file is valid."
else
    echo "Error: Reverse zone file is invalid."
fi

# Enable and start named service
systemctl enable named
systemctl restart named
sleep 5

# Check if a service is enabled and running
check_service() {
    service_name=$1

    if systemctl is-enabled "$service_name" &>/dev/null; then
        echo "$service_name service is enabled."
    else
        echo "Error: $service_name service is not enabled."
    fi

    if systemctl is-active "$service_name" &>/dev/null; then
        echo "$service_name service is running."
    else
        echo "Error: $service_name service is not running."
    fi
}

# List of services to check
services=("named")

# Check status of all services
for service in "${services[@]}"; do
    check_service "$service"
done

# List of hostnames and IP addresses to check
hostnames=(
    "api.$CLUSTER_NAME.$BASE_DOMAIN"
    "api-int.$CLUSTER_NAME.$BASE_DOMAIN"
    "$MASTER01_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN"
    "$MASTER02_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN"
    "$MASTER03_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN"
    "$WORKER01_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN"
    "$WORKER02_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN"
    "$MASTER01_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN"
    "$BASTION_IP"
    "$MASTER01_IP"
    "$MASTER02_IP"
    "$MASTER03_IP"
    "$WORKER01_IP"
    "$WORKER02_IP"
    "$BOOTSTRAP_IP"
)

# Loop through hostnames and perform nslookup
all_successful=true
failed_hostnames=()

for hostname in "${hostnames[@]}"; do
    nslookup_result=$(nslookup "$hostname" 2>&1)
    if [ $? -ne 0 ]; then
        all_successful=false
        failed_hostnames+=("$hostname")
    fi
done

# Display results
if [ "$all_successful" = true ]; then
    echo "All DNS resolutions were successful."
else
    echo "DNS resolution failed for the following hostnames:"
    for failed_hostname in "${failed_hostnames[@]}"; do
        echo "$failed_hostname"
    done
fi

#######################################################


echo ====== Setup haproxy services ======
# Setup haproxy services configuration
cat << EOF > /etc/haproxy/haproxy.cfg 
global
  log         127.0.0.1 local2
  pidfile     /var/run/haproxy.pid
  maxconn     4000
  daemon

defaults
  mode                    http
  log                     global
  option                  dontlognull
  option http-server-close
  option                  redispatch
  retries                 3
  timeout http-request    10s
  timeout queue           1m
  timeout connect         10s
  timeout client          1m
  timeout server          1m
  timeout http-keep-alive 10s
  timeout check           10s
  maxconn                 3000

frontend stats
  bind *:1936
  mode            http
  log             global
  maxconn 10
  stats enable
  stats hide-version
  stats refresh 30s
  stats show-node
  stats show-desc Stats for ocp4 cluster 
  stats auth admin:passwd
  stats uri /stats

listen api-server-6443 
  bind $BASTION_IP:6443
  mode tcp
  server     $BOOTSTRAP_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN $BOOTSTRAP_IP:6443 check inter 1s backup
  server     $MASTER01_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN $MASTER01_IP:6443 check inter 1s
  server     $MASTER02_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN $MASTER02_IP:6443 check inter 1s
  server     $MASTER03_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN $MASTER03_IP:6443 check inter 1s

listen machine-config-server-22623 
  bind $BASTION_IP:22623
  mode tcp
  server     $BOOTSTRAP_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN $BOOTSTRAP_IP:22623 check inter 1s backup
  server     $MASTER01_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN $MASTER01_IP:22623 check inter 1s
  server     $MASTER02_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN $MASTER02_IP:22623 check inter 1s
  server     $MASTER03_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN $MASTER03_IP:22623 check inter 1s

listen default-ingress-router-80
  bind $BASTION_IP:80
  mode tcp
  balance source
  server     $WORKER01_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN $WORKER01_IP:80 check inter 1s
  server     $WORKER02_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN $WORKER02_IP:80 check inter 1s

listen default-ingress-router-443
  bind $BASTION_IP:443
  mode tcp
  balance source
  server     $WORKER01_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN $WORKER01_IP:443 check inter 1s
  server     $WORKER02_HOSTNAME.$CLUSTER_NAME.$BASE_DOMAIN $WORKER02_IP:443 check inter 1s
EOF
echo "Haproxy service configuration is completed."

# Path to HAProxy configuration file
CONFIG_FILE="/etc/haproxy/haproxy.cfg"

# Check HAProxy configuration syntax
check_haproxy_config() {
    haproxy -c -f "$CONFIG_FILE"
    if [ $? -eq 0 ]; then
        echo "HAProxy configuration is valid."
    else
        echo "HAProxy configuration is invalid."
    fi
}

# Call the function to check HAProxy configuration
check_haproxy_config

# Enable and start HAProxy service
systemctl enable haproxy
systemctl start haproxy
sleep 5

# Check if a service is enabled and running
check_service() {
    service_name=$1

    if systemctl is-enabled "$service_name" &>/dev/null; then
        echo "$service_name service is enabled."
    else
        echo "Error: $service_name service is not enabled."
    fi

    if systemctl is-active "$service_name" &>/dev/null; then
        echo "$service_name service is running."
    else
        echo "Error: $service_name service is not running."
    fi
}

# List of services to check
services=("haproxy")

# Check status of all services
for service in "${services[@]}"; do
    check_service "$service"
done
