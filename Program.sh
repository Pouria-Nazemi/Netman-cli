#!/bin/bash

get_nft_backup() {
    sudo cp /etc/nftables.conf /etc/nftables.conf.backup
    echo "A backup of nftables.conf saved in -- /etc/nftables.conf.backup --"
    sleep 0.5
}

restore_nft_backup() {
    file_path="/etc/nftables.conf.backup" 

    if [ -f "$file_path" ]; then
       sudo mv /etc/nftables.conf.backup /etc/nftables.conf
       echo "The last Backup of nftables config Restored."
    else
       echo "No backup file found!"
fi
    sleep 0.5
}

get_DNS_backup() {
    sudo cp /etc/resolv.conf /etc/resolv.conf.bak
    echo "A backup of DNS config saved in -- /etc/resolv.conf.bak --"
    sleep 0.5
}
restore_DNS_backup(){
    sudo mv /etc/resolv.conf.bak /etc/resolv.conf
    echo "The last Backup of DNS config Restored."
    sleep 0.5
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


validate_ip() {
    local ip_address=$1
    
    # Split the IP address into octets
    IFS='.' read -ra octets <<< "$ip_address"
    
    # Check if there are 4 octets
    if [ "${#octets[@]}" -ne 4 ]; then
        return 1
    fi
    
    # Validate each octet
    for octet in "${octets[@]}"; do
        # Ensure that each octet is a number between 0 and 255
        if ! [[ "$octet" =~ ^[0-9]+$ ]] || [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ]; then
            return 1
        fi
    done
    
    return 0
}

check_dns() {
    dns_ip=$1
    if ! nslookup -retry=1 google.com $dns_ip >/dev/null; then
        return 0  # DNS server is not reachable
    else
        return 1  # DNS server is reachable
    fi
}

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
    # Select table
        #read -p "Enter the name of the new table: " table
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

          # Prompt for chain priority
          while true; do
              read -p "Enter the priority of the chain (default is 0): " chain_priority
              if [[ $chain_priority =~ ^[0-9]+$ ]]; then
                  break
              else
                  echo "Invalid chain priority entered. Please provide a numeric value."
              fi
          done
         echo "Select ploicy:"
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
    

          # Prompt for chain name
          read -p "Enter the name of the chain to remove: " chain_name

          # Check if the chain exists
          if ! validate_chain "$table" "$chain_name"; then
              echo "Chain '$chain_name' does not exist in table '$table'."
              exit 1
          fi

          # Remove the chain from the table
          remove_chain "$table" "$chain_name"
}

validate_table() {
  local table_name=$1
  nft list tables | grep -q "$table_name"
}

# Function to validate if chain exists in a table
validate_chain() {
  local table_name=$1
  local chain_name=$2
  nft list chains "$table_name" | grep -q "chain $chain_name "
}



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

change_hostname() {
    read -p "Enter your desired hostname: " new_hostname
    sudo echo "$new_hostname" | sudo tee /etc/hostname > /dev/null
    sudo sed -i "s/127.0.1.1.*/127.0.1.1\t$new_hostname/g" /etc/hosts
    sudo hostnamectl set-hostname "$new_hostname"
    echo "Hostname changed to '$new_hostname'. Reboot is needed for changes to take effect."

}

select_interface() {
    # List all interfaces
    interfaces=$(ip link show | awk -F': ' '/^[0-9]+:/{print $2}')

    # Prompt the user to select an interface
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
    sudo cp /etc/network/interfaces /etc/network/interfaces.bak

    # Configure the interface
    echo "
    auto $INTERFACE
    iface $INTERFACE inet static
        address $IP_ADDRESS
        netmask $NETMASK
        gateway $GATEWAY
    " | sudo tee -a /etc/network/interfaces > /dev/null

    sudo dhclient -r $INTERFACE

    # Restart networking service
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

set_dhcp_temporarily() {
    interface=$(select_interface)
    sudo dhclient "$interface"
}

set_dhcp_permanently() {
    interface=$(select_interface)
    config_file="/etc/netplan/01-netcfg.yaml"  # Adjust this path based on your Ubuntu version

    # Check if the config file exists
    if [ -f "$config_file" ]; then
        # Modify the config file to enable DHCP
        sudo sed -i "s/dhcp4: no/dhcp4: yes/" "$config_file"

        # Apply the new configuration
        sudo netplan apply
        echo "DHCP has been set permanently for $interface."
    else
        echo "Netplan configuration file not found."
    fi
}

add_temporary_root_user() {
    read -p "Enter username for temporary root access: " username
    read -s -p "Enter password for $username: " password
    echo ""

    # Add user with root privileges
    useradd -ou 0 -g 0 -m $username

    # Set the password for the user
    echo "$username:$password" | chpasswd

    echo "Temporary root user ($username) added successfully."
}

ssh_restriction(){
        # Read IP or range of IPs from user input
    read -p "Enter the IP address or range of IPs (CIDR notation) to allow SSH access: " IP_OR_RANGE
    
    SSH_PORT="22"

    nft insert rule filter input ip saddr $IP_OR_RANGE tcp dport $SSH_PORT counter accept

# Save the ruleset with the new rule appended
    nft list ruleset | sed '$d' > /etc/nftables.conf.tmp
    echo >> /etc/nftables.conf.tmp
    echo 'include "/etc/nftables.conf"' >> /etc/nftables.conf.tmp

    # Replace the original configuration file with the modified temporary file
    mv /etc/nftables.conf.tmp /etc/nftables.conf
}

ip_route_temp(){
    read -p "Enter the destination network (CIDR notation): " destination_network
    read -p "Enter the gateway IP: " gateway_ip

    # Add the temporary static route
    ip route add $destination_network via $gateway_ip

    # Verify the added route
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

    # Define variables
    config_file="/etc/network/interfaces"
    backup_file="${config_file}.bak"

    # Backup the original config file
    cp $config_file $backup_file

    # Append the static route configuration to the config file
    echo "up route add -net $destination_network gw $gateway_ip" >> $config_file

    # Restart the network service
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

select_ip_route(){
    echo "Available IP Routes:"
    ip route show
    echo ""

    # Prompt the user to select a route
    read -p "Enter the number corresponding to the IP route you want to delete: " selected_num

    selected_route=$(ip route show | awk 'NR=='$selected_num' {print $0}')

    if [[ -z "$selected_route" ]]; then
        echo "Invalid selection. Exiting."
        exit 1
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
            echo "Invalid choice. Exiting."
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
    22) select_ip_route ;; 
    23) ssh_restriction ;;

    *) display_help ;;
  esac
done

