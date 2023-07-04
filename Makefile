install:
    sudo apt-get update
    sudo apt-get install -y dnsutils
	sudo apt-get install -y dhcp-client

run: install
	sudo chmod Program.sh
    sudo bash Program.sh