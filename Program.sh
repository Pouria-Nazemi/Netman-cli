#!/bin/bash

##### controlers

validate_ip() {
    local ip_address=$1
    
    # octets
    IFS='.' read -ra octets <<< "$ip_address"
    
    # 4 octets
    if [ "${#octets[@]}" -ne 4 ]; then
        return 1
    fi
    
    # Validation
    for octet in "${octets[@]}"; do
        if ! [[ "$octet" =~ ^[0-9]+$ ]] || [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ]; then
            return 1
        fi
    done
    
    return 0
}

# check existent
validate_table() {
  local table_name=$1
  nft list tables | grep -q "$table_name"
}

validate_chain() {
  local table_name=$1
  local chain_name=$2
  nft list chains "$table_name" | grep -q "chain $chain_name "
}

#####
####################### Phase 1 ############################
##### DNS Part

get_DNS_backup() {
    sudo cp /etc/resolv.conf /etc/resolv.conf.bak
    echo "A backup of DNS config saved in -- /etc/resolv.conf.bak --"
}

restore_DNS_backup(){
    sudo mv /etc/resolv.conf.bak /etc/resolv.conf
    echo "The last Backup of DNS config Restored."
}

change_dns() {
    read -p "Enter the new DNS IP: " dns_ip
    if  ! validate_ip "$dns_ip"; then
        echo "IP: '$dns_ip' is not valid."
        return
    elif ! check_dns "dns_ip"; then
            echo "$dns_ip does not response as DNS server"
            return
        else
            echo "nameserver" "$dns_ip" | sudo tee /etc/resolv.conf > /dev/null
            echo "DNS settings changed."

    fi
}

check_dns() {
    dns_ip=$1
    if ! nslookup -retry=1 google.com $dns_ip >/dev/null; then
        return 0  # not reachable
    else
        return 1  # reachable
    fi
}

#####
##### Hostname

change_hostname() {
    read -p "Enter your desired hostname: " new_hostname
    sudo echo "$new_hostname" | sudo tee /etc/hostname > /dev/null
    sudo sed -i "s/127.0.1.1.*/127.0.1.1\t$new_hostname/g" /etc/hosts
    sudo hostnamectl set-hostname "$new_hostname"
    echo "Hostname changed to '$new_hostname'. Reboot is needed for changes to take effect."
}

#####
##### IP set on interface


select_interface() {
    # List all interfaces
    interfaces=$(ip link show | awk -F': ' '/^[0-9]+:/{print $2}')

    # select an interface by user
    PS3="Select an interface: "
    select interface in $interfaces; do
        if [[ -n "$interface" ]]; then
            echo "Selected interface: $interface"
            break
        else
            echo "Invalid option. Please try again."
        fi
    done
    echo "$interface"
}


set_permanent_ip(){
    INTERFACE=$(select_interface)
    read -p "Enter your desired IP address: " IP_ADDRESS
    if ! validate_ip "$IP_ADDRESS"; then
        echo "IP: '$IP_ADDRESS' is not valid."
        return
    fi
    read -p "Enter netmask: " NETMASK
    read -p "Enter Gateway IP:" GATEWAY

    if ! validate_ip "$GATEWAY"; then
        echo "IP: '$GATEWAY' is not valid."
        return
    fi

    # Backup the original file
    # sudo cp /etc/network/interfaces /etc/network/interfaces.bak

    # Configure the interface
    echo "
    auto $INTERFACE
    iface $INTERFACE inet static
        address $IP_ADDRESS
        netmask $NETMASK
        gateway $GATEWAY
    " | sudo tee -a /etc/network/interfaces > /dev/null

    # release dhcp IP
    sudo dhclient -r $INTERFACE

    # Restart network service
    sudo systemctl restart networking.service
    sudo dhclient -r $INTERFACE
    echo "IP address $IP_ADDRESS permanently set on interface $INTERFACE."
}

set_temporary_ip() {
    INTERFACE=$(select_interface)
    read -p "Enter your desired IP address: " IP_ADDRESS
    if ! validate_ip "$IP_ADDRESS"; then
        echo "IP: '$IP_ADDRESS' is not valid."
        return
    fi

    read -p "Enter netmask: " NETMASK
    read -p "Enter Gateway IP:" GATEWAY

    if ! validate_ip "$GATEWAY"; then
        echo "IP: '$GATEWAY' is not valid."
        return
    fi

    if sudo ifconfig $INTERFACE $IP_ADDRESS netmask $NETMASK; then
        echo "IP address $IP_ADDRESS temporarily set on interface $INTERFACE."
        sudo dhclient -r $INTERFACE
    else
        echo "An error occurred while configuring the interface."
    fi
}

#####
##### DHCP Part

set_dhcp_temporarily() {
    interface=$(select_interface)
    sudo dhclient "$interface"
}

set_dhcp_permanently() {
    interface=$(select_interface)
    config_file="/etc/netplan/01-netcfg.yaml"  # TODO check address

    if [ -f "$config_file" ]; then
        sudo sed -i "s/dhcp4: no/dhcp4: yes/" "$config_file"

        sudo netplan apply
        echo "DHCP has been set permanently for $interface."
    else
        echo "Netplan configuration file not found."
    fi
}

#####
##### add or remove route
ip_route_temp(){
    read -p "Enter the destination network (CIDR notation): " destination_network
    read -p "Enter the gateway IP: " gateway_ip

    ip route add $destination_network via $gateway_ip

    if [[ $? -eq 0 ]]; then
        echo "Temporary static route added successfully:"
        ip route show $destination_network
    else
        echo "Failed to add temporary static route."
    fi
}

ip_route_perm(){

    read -p "Enter the destination network (CIDR notation): " destination_network
    read -p "Enter the gateway IP: " gateway_ip

    config_file="/etc/network/interfaces"
    backup_file="${config_file}.bak"

    # Backup the original config file
    cp $config_file $backup_file

    echo "up route add -net $destination_network gw $gateway_ip" >> $config_file

    service networking restart

    # Check if the restart was successful
    if [[ $? -eq 0 ]]; then
        echo "Permanent static route added successfully."
    else
        echo "Failed to add permanent static route."
        # Restore the backup file
        cp $backup_file $config_file
        service networking restart
        echo "Network service restarted with the original configurations."
    fi

}

select_ip_route_to_delete(){
    echo "Available IP Routes:"
    ip route show
    echo ""

    # select a route by user
    read -p "Enter the number corresponding to the IP route you want to delete: " selected_num

    selected_route=$(ip route show | awk 'NR=='$selected_num' {print $0}')

    if [[ -z "$selected_route" ]]; then
        echo "Invalid selection."
        retrun 1
    fi
    echo "Selected Route: $selected_route"
    echo "Select Deletion Type:"
    echo "1. Permanent Deletion"
    echo "2. Temporary Deletion"

    read -p "Enter your choice (1 or 2): " deletion_type

    case $deletion_type in
        1)
            # Delete the selected route permanently
            delete_route_permanent "$selected_route"
            ;;
        2)
            # Delete the selected route temporarily
            delete_route_temporary "$selected_route"
            ;;
        *)
            echo "Invalid choice."
            retun 1
            ;;
    esac
}

delete_route_temporary() {
    local route="$1"
    sudo ip route delete "$route"
    echo "Route $route has been temporarily deleted."
}

delete_route_permanent() {
    local route="$1"
    sudo ip route del "$route"
    echo "Route $route has been permanently deleted."
}
#####


####################### Phase 2_1 ############################
##### ssh restriction

ssh_restriction(){
    read -p "Enter the IP address or range of IPs (CIDR notation) to allow SSH access: " IP_OR_RANGE
    
    SSH_PORT="22"

    nft insert rule filter input ip saddr $IP_OR_RANGE tcp dport $SSH_PORT counter accept

    # Save the ruleset with the new rule appended
    nft list ruleset | sed '$d' > /etc/nftables.conf.tmp
    echo >> /etc/nftables.conf.tmp
    echo 'include "/etc/nftables.conf"' >> /etc/nftables.conf.tmp
    mv /etc/nftables.conf.tmp /etc/nftables.conf
}

#####
##### flush all rules

flush_nftables(){
    sudo nft flush ruleset
}

#####
##### redirection 4.2.2.4 dns to 1.1.1.1

redirection_udp_dns(){
    nft add table inet redirectDns
    nft add chain inet redirectDns mychain { type filter hook prerouting priority -150 \; }
    nft add rule inet redirectDns mychain ip daddr 4.2.2.4 udp dport 53 counter redirect to :53-1.1.1.1

    echo "redirection done"
}

#####
##### Internet unreachability

restrict_Internet(){
    # Detect the internal network interface
    internet_interface=$(ip route | awk '/default/ {print $5}')
    if [[ -z "$internet_interface" ]]; then
        echo "Unable to detect internal network interface. Please configure it manually."
        interface=$(select_interface)
    fi

    nft add table inet filter
    nft add chain inet filter input { type filter hook input priority 0 \; }
    nft add chain inet filter output { type filter hook output priority 0 \; }
    nft add rule inet filter input iifname "$internet_interface" drop
    nft add rule inet filter output oifname "$internet_interface" drop

    echo "nftables rules configured successfully."

}

#####
##### make nftables config permenant

permanent_nft(){
    sudo nft list ruleset > /etc/nftables.conf
    sudo systemctl enable nftables
}

#####
####################### Phase 2_1 ############################
##### backup
get_nft_backup() {
    sudo cp /etc/nftables.conf /etc/nftables.conf.backup
    echo "A backup of nftables.conf saved in -- /etc/nftables.conf.backup --"
}

restore_nft_backup() {
    file_path="/etc/nftables.conf.backup" 

    if [ -f "$file_path" ]; then
       sudo mv /etc/nftables.conf.backup /etc/nftables.conf
       echo "The last Backup of nftables config Restored."
    else
       echo "No backup file found!"
    fi
}
#####
##### show table
show_all_tables(){
    nft list ruleset
}

show_specified_table(){
    read -p "Enter the name of the table to show: " table_name
    if validate_table "$table_name"; then
        nft list ruleset | grep ".*$table_name"
    else
        echo "Selected table does not exist. Please choose a valid table."
    fi
}
#####
##### nftables add and remove

create_nftable() {
  echo "Create Table"
  echo "--------------"
  read -p "Enter the table name: " table_name
  if ! nft list tables | grep -wq "$table_name"; then
    select family in inet ip ip6; do
        if [[ "$REPLY" =~ ^[1-4]$ ]]; then
            break
        fi
        echo "Wrong input for choosing family"
    done
    nft add table "$family" "$table_name"
    echo "Table '$table_name' created."
  else
    echo "Table '$table_name' already exists."
  fi
}

remove_nftable() {

    read -p "Enter the table name: " table_name

    if nft list tables | grep -q "$table_name"; then

        nft flush table "$table_name"
        nft delete table "$table_name"
        echo "Successfully removed nftable: $table_name"
    else
        echo "nftable $table_name does not exist."
    fi
}

#####
##### chain create and remove

add_chain() {
  local table_name=$1
  local chain_name=$2
  local chain_type=$3
  local hook=$4
  local chain_priority=$5
  local policy=$6

  
  nft add chain "$table_name" "$chain_name" { type "$chain_type" hook "$hook" priority "$chain_priority"\; policy "$policy"\; }
  
  echo "Successfully added the following chain:"
  echo "---------------------------------------"
  echo "Table: $table_name"
  echo "Chain: $chain_name"
  echo "Type: $chain_type"
  echo "Priority: $chain_priority"
  echo "Policy: $policy"
}

remove_chain() {
  local table_name=$1
  local chain_name=$2

  nft delete chain "$table_name" "$chain_name"

  echo "Successfully removed the following chain:"
  echo "-----------------------------------------"
  echo "Table: $table_name"
  echo "Chain: $chain_name"
}

add_chain_handler(){
    tables=$(nft list tables | awk '{print $NF}')

    # select a table
    echo "Select a table: "
    select table in ${tables[@]}; do
    if validate_table "$table"; then
        echo "Selected table: $table"
        break
    else
        echo "Invalid selection. Try again."
    fi
    done

    read -p "Enter the name of the new chain: " chain_name

    # Select chain type
    echo "Select chain type:"
    select chain_type in filter route nat; do
        break
    done
        echo "Select hook:"
        select hook in input output forward prerouting postrouting; do
            break
        done

        # chain priority
        while true; do
            read -p "Enter the priority of the chain (default is 0): " chain_priority
            if [[ $chain_priority =~ ^[0-9]+$ ]]; then
                break
            else
                echo "Invalid chain priority entered. Please provide a numeric value."
            fi
        done
        # chain policy
        echo "Select policy:"
        select policy in accept drop; do
            break
        done
        # Add the chain to the table
        add_chain "$table" "$chain_name" "$chain_type" "$hook" "$chain_priority" "$policy"
}

remove_chain_handler(){
     # Select table
        tables=$(nft list tables | awk '{print $NF}')

        # Prompt the user to select a table
        echo "Select a table: "
        select table in ${tables[@]}; do
        if validate_table "$table"; then
            echo "Selected table: $table"
            break
        else
            echo "Invalid selection. Try again."
        fi
        done
          # get chain name
          read -p "Enter the name of the chain to remove: " chain_name

          # Check if the chain exists
          if ! validate_chain "$table" "$chain_name"; then
              echo "Chain '$chain_name' does not exist in table '$table'."
              return 1
          fi
          remove_chain "$table" "$chain_name"
}

#####
##### addd rules


add_rule(){
    echo "Add Rule selected!"
    
    # Prompt for user inputs
    tables=$(nft list tables | awk '{print $NF}')

    # Prompt the user to select a table
    echo "Select a table: "
    select table in ${tables[@]}; do
        if validate_table "$table"; then
            echo "Selected table: $table"
            break
        else
            echo "Invalid selection. Try again."
        fi
    done
    read -p "Enter chain name: " chain_name

 #   if ! validate_chain "$table" "$chain_name"; then
 #           echo "Chain '$chain_name' does not exist in table '$table'."
 #           return
 #   fi

    read -p "Enter source IP (leave empty for any): " source_ip

    read -p "Enter destination IP (leave empty for any): " dest_ip

    echo -p "Select protocol: "
    select protocol in tcp udp icmp none; do
        if [[ $REPLY =~ ^[0-4]$ ]]; then
                break
        fi
    done
    read -p "Enter source port (leave empty for any): " source_port
    read -p "Enter destination port (leave empty for any): " dest_port

    rule="add rule $table $chain_name"
    
 #   select policy in accept drop;do
 #       if [[ $REPLY =~ ^[1-2]$ ]]; then
 #               break
 #      fi
 #  done

    if [[ ! -z $source_ip ]]; then
        if ! validate_ip "$source_ip"; then
            echo "IP: '$source_ip' is not valid."
            return
        fi
        rule+=" ip saddr $source_ip"
    fi
    
    if [[ ! -z $dest_ip ]]; then
        if ! validate_ip "$dest_ip"; then
            echo "IP: '$dest_ip' is not valid."
            return
        fi
        rule+=" ip daddr $dest_ip"
    fi
    
    if [[ ! "$protocol" == "none" ]]; then
        rule+=" $protocol"
    fi
    
    if [[ ! -z $source_port ]]; then
        rule+=" sport $source_port"
    fi
    
    if [[ ! -z $dest_port ]]; then
        rule+=" dport $dest_port"
    fi

    rule+=" accept"

    
    # Apply the rule using the nft command
    sudo nft "$rule"
}


#####
##### NAT rules part


nat_rules_menu() {
    clear
    echo "Available commands:"
    echo "1. Add Source NAT (SNAT) rule."
    echo "2. Add Destination NAT (DNAT) rule."
    echo "3. Add Port Forwarding rule."
    echo "4. Add Masquerading rule."
    echo "5. Help: Show available commands."
    nat_rules_menu_handler
}

nat_rules_menu_handler() {
    read -p "Enter a command number (5 for available commands, 6 to exit): " menu_option

    case "$menu_option" in
        1)
            add_snat_rule
            ;;
        2)
            add_dnat_rule
            ;;
        3)
            add_port_forwarding_rule
            ;;
        4)
            add_masquerade_rule
            ;;
        5)
            help_command
            ;;
        6)
            break
            ;;
        *)
            echo "Invalid command number. Please try again."
            ;;
    esac

}

add_snat_rule() {
    read -p "Enter the source IP address: " source_ip
    nft add rule nat postrouting ip saddr "$source_ip" counter masquerade
    echo "Done!"
}

add_dnat_rule() {
    read -p "Enter the interface: " interface
    read -p "Enter the destination port: " destination_port
    read -p "Enter the internal address: " internal_address
    read -p "Enter the internal port: " internal_port
    nft add rule nat prerouting iif "$interface" tcp dport "$destination_port" counter dnat to "$internal_address":"$internal_port"
    echo "Done!"    
}

add_port_forwarding_rule() {
    read -p "Enter the interface: " interface
    read -p "Enter the external port: " external_port
    read -p "Enter the internal address: " internal_address
    read -p "Enter the internal port: " internal_port
    nft add rule nat prerouting iif "$interface" tcp dport "$external_port" counter dnat to "$internal_address":"$internal_port"
    echo "Done!"

}

add_masquerade_rule() {
    read -p "Enter the internal subnet: " internal_subnet
    nft add rule nat postrouting ip saddr "$internal_subnet" counter masquerade
    echo "Done!"
}



#####

menu() {
  echo "
  
  
    "
  echo " Welcome to netman-cli"
  echo "----------------"
  echo "Choose the number of option you want: "
  echo "1. Provide backup of the current nftables"
  echo "2. Restore last backup of nftable"
  echo "3. Create Table"
  echo "4. Remove Table"
  echo "5. Add chain"
  echo "6. Remove a chain"
  echo "7. add rule"
  echo "8. remove rule"
  echo "9. Add nat rules"
  echo "10. Show all tables"
  echo "11. Show table by name"
  echo "12. DNS change"
  echo "13. Backup DNS config"
  echo "14. Restore last backup of DNS config"
  echo "15. change hostname"
  echo "16. permenant static ip config on a interface"
  echo "17. temproray static ip config on a interface"
  echo "18. dhcp enable on a interface permenantly"
  echo "19. dhcp enable on a interface temproray"
  echo "20. add permenant root"
  echo "21. add temproray root"
  echo "22. delete a ip route"
  echo "23. ssh restriction"
  echo "24. remove all rules of firewall"
  echo "25. redirect packets of 4.2.2.4:53 to 1.1.1.1:53"
  echo "26. make Internet unreachable"
  echo "27. make nftables config permenant"

}


while true; do
  menu

  read -p "Enter your choice: " choice
  case $choice in
    1) get_nft_backup ;;
    2) restore_nft_backup ;;
    3) create_nftable ;;
    4) remove_nftable ;;
    5) add_chain_handler ;;
    6) remove_chain_handler ;;
    7) add_rule ;;
    8) remove_rule ;;
    9) nat_rules_menu ;;
    10) show_all_tables ;;
    11) show_specified_table ;;
    12) change_dns ;;
    13) get_DNS_backup ;;
    14) restore_DNS_backup ;;
    15) change_hostname ;;
    16) set_permanent_ip ;;
    17) set_temporary_ip ;;
    18) set_dhcp_permanently ;;
    19) set_dhcp_temporarily ;;
    20) ip_route_perm ;;
    21) ip_route_temp ;;
    22) select_ip_route_to_delete ;; 
    23) ssh_restriction ;;
    24) flush_nftables ;;
    25) redirection_udp_dns ;;
    26) restrict_Internet ;;
    27) permanent_nft ;;
    *) echo "Wrong selection input"
        continue ;;
  esac
done

