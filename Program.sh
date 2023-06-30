#!/bin/bash

menu() {
  clear
  echo "Welcome to netman-cli"
  echo "----------------"
  echo "1. Create Table"
  echo "2. Remove Table"
  echo "3. Provide backup of the current nftables"
  echo "4. Exit"
  echo
}

get_backup() {
    sudo cp /etc/nftables.conf /etc/nftables.conf.backup
    echo "A backup of nftables.conf saved in -- /etc/nftables.conf.backup --"
}

create_nftable() {
  clear
  echo "Create Table"
  echo "--------------"
  read -p "Enter the table name: " table_name
  if ! nft list tables | grep -wq "$table_name"; then
    nft add table "$table_name"
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


while true; do
  menu

  read -p "Enter your choice: " choice

  case $choice in
    1) create_nftable ;;
    2) Remove Table ;;
    3) get_backup ;;
    4) exit ;;
    *) display_help ;;
  esac
done