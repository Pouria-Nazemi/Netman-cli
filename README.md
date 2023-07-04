# NETMAN CLI
## _Linux Machine Simple Network Management Wrapper_

Dillinger is a cloud-enabled, mobile-ready, offline-storage compatible,
AngularJS-powered HTML5 Markdown editor.

 No matter how much you know about network configuration on linux, it provides user-friendly interface for you to do your needs in the easiest way and check inputs to avoid any misinput configuration.

## Features
### nftables
    -backup and restore configs
    -creating or removing new tables and chain
    -add or remove rules(become able in next version SOON)
    -adding main nat rules
### firewall basic rules (base on nftables)
    -restrict IP`s that can make ssh connection to the machine
    -remove all rules on the firewall
    -make configs of nftables permenant
    -restrict machine to access to the Internet and not be reachable from Internet
    -restrict a specified user on machine to access Internet
### set IP on interfaces
    -set permenant or temperorary static IP on a interface
    -set permenant or temperorary DHCP IP on a interface
    
### ip route
    -add or delete a ip route permenantly or temprorary

### dns setting
    -change machine DNS IP
    -backup or restore DNS config

## How to use it:
It doesn`t take you any special effort to use it.
You just need to give execution access to the file and then run it at the root user stage.
The Provided CLI Menus are fully-understandable and by the features section you are able to find what at what submenu.

What you need to do is only execute this command at the project folder with root privilage:
```sh
make run
```

Feel free to use it and if there is any problem contact me with:
pourianazemi80@gmail.com
