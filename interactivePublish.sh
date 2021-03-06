#!/bin/bash

echo
echo "Verifying kbfs...";
echo

KBFS_MOUNT=$(keybase status | grep mount | cut -f 2 -d: | sed -e 's/^\s*//' -e '/^$/d');

## Restart Keybase if needed

if [ ! -d "$KBFS_MOUNT" ]; then
	echo "KBFS is not running!";
	run_keybase
	sleep 3
else
	echo "KBFS mount point: $KBFS_MOUNT";
fi

np=1;
echo -e "\n\n----- >> Interactive peer info builder << ------\n";

if [[ $1 != "new" ]]; then
	if [[ -f ./peerInfo.temp ]]; then
		echo -e '\nCached data on peerInfo.temp\n'
		source peerInfo.temp;
		cat peerInfo.temp | grep "_$np_";
		echo -e '\nEnd of cached data.\n\n';
	else
		echo -e "## Temp settings" > peerInfo.temp;
	fi
else
	echo -e "## Temp settings" > peerInfo.temp;
fi

inc() {
	((np++))
}

function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

set_peer_number() {
	echo "Editing peer number: $1";
	np="$1";
}

edit() {
	max=8
	echo -e " > Select a peer number to edit: 1-$max \c"
	read
	set_peer_number "$REPLY";
}

choose_action() {
	echo -e "\n --- MENU ---\n";
	PS3=' > Please select your action: '
	options=("New Peer" "Edit" "Done")
	select opt in "${options[@]}"
	do
		case $opt in
			"New Peer")
				echo "New peer selected";
				new=true;
				((np++))
				new_peer;
				;;
			"Edit")
				echo "Edit peers"
				edit;
				;;
			"Done")
				save;
				echo -e "\n > Quitting...";
				exit 1;
				break
				;;
			*) echo invalid option;;
		esac
	done
}

echoParam()
{
	FIELD=$1;
	VALUE=$2;
	NET_ADDR=$3
	lineData=$(case "$FIELD" in
		"IP" ) echo "AllowedIPs = $VALUE/32"
			;;
		"PublicKey" ) echo "PublicKey = $VALUE="
			;;
		"Endpoint" ) echo "Endpoint = $VALUE"
			;;
		"PKA" ) echo "PersistentKeepAlive = $VALUE"
			;;
		"PUB" ) echo "peer-key = \"$VALUE\""
			;;
		"P2P" ) echo "p2p-peer-address = $NET_ADDR:$VALUE"
			;;
	esac)
	echo "$lineData" >> my-peer-info;
}

convert() {
	current_peer=0;
	current_cat="";
	while read line; do
		if [[ $line != "" ]] && [[ $line != \#* ]]; then
			key=$(echo "$line" | cut -f1 -d'=');
			value=$(echo "$line" | cut -f2 -d'=' | sed -e 's/^"//' -e 's/"$//');
			cat=$(echo "$key" | cut -f1 -d'_');
			pos=$(echo "$key" | cut -f2 -d'_');
			field=$(echo "$key" | cut -f3 -d'_');
			if [[ $cat != $current_cat ]] || (( pos != current_peer)); then
				if (( pos != current_peer)); then
					NET_IP="$value";
				fi
				current_peer="$pos";
				current_cat="$cat";
				if [[ $cat == "EOS" ]]; then
					echo -e "\n[EOS]" >> my-peer-info;
				fi
				if [[ $cat == "WG" ]]; then
					echo -e "\n[Peer]" >> my-peer-info;
				fi
			fi
			echoParam "$field" "$value" "$NET_IP";
		fi
	done < peerInfo.temp
}

save() {
	echo
	echo -e " > Do you want to save your settings? [y/n] \c"
	read
	if [[ "$REPLY" = "y" || "$REPLY" = "" ]]; then
		echo -e "\nWriting to file...";

		echo -e "\n------- START -------\n";
		echo "## Created with interactivePublish.sh" > my-peer-info;
		convert;
		cat my-peer-info;
		publish;
		echo -e "\n------- END ---------"
	else
		echo "my-peer-info wasn't touched!";
	fi
}

publish() {
	echo
	echo -e " > Do you want to publish now using keybase? [y/n] \c"
	read
	if [[ "$REPLY" = "y" || "$REPLY" = "" ]]; then
		./publishPeerInfo.sh my-peer-info;
	else
		echo "my-peer-info saved. You will have to publish later...";
	fi
}

edit_wg() {
	echo
	echo -e " > WG Peer $np ip address [192.168.100.0 to 192.168.103.255]\n Current value: ${var[WG_IP_$np]} \c"
	read
	let "WG_IP_$np"="$REPLY";
}

wg_ip() {
	varname='WG_'$np'_IP'
	if [[ "${!varname}" == "" || $new == true ]]; then
		echo -e " > WG Peer $np ip address [192.168.100.0 to 192.168.103.255]: \c"
		read
		if valid_ip $REPLY; then
			if [[ "$REPLY" = "" ]]; then
				exit 1;
			else
				declare "$varname"="$REPLY";
				# ls ~/kbfs/team/eos_ghostbusters/ip_list/ | grep $WG_IP
				echo "$varname=\"${!varname}\"" >> peerInfo.temp;
			fi
		else
			echo -e "\n Invalid IP Address: $REPLY \n"
			wg_ip;
		fi
	fi
}

wg_pubkey() {
	varname='WG_'$np'_PublicKey'
	if [[ "${!varname}" == "" || $new == true ]]; then
		echo -e " > WG Peer $np PublicKey: \c"
		read
		if [[ "$REPLY" = "" ]]; then
			exit 1;
		else
			declare "$varname"="$REPLY";
			echo "$varname=\"${!varname}\"" >> peerInfo.temp;
		fi
	fi
}

wg_endpoint() {
	varname='WG_'$np'_Endpoint'
	if [[ "${!varname}" == "" || $new == true ]]; then
		echo -e " > WG Peer $np Endpoint [host:port]: \c"
		read
		if [[ "$REPLY" = "" ]]; then
			exit 1;
		else
			declare "$varname"="$REPLY";
			echo "$varname=\"${!varname}\"" >> peerInfo.temp;
		fi
	fi
}

wg_pka() {
	varname='WG_'$np'_PKA'
	if [[ "${!varname}" == "" || $new == true ]]; then
		echo -e " > WG Peer $np PersistentKeepAlive [default=20]: \c"
		read
		if [[ "$REPLY" = "" ]]; then
			declare "$varname"="20";
		else
			declare "$varname"="$REPLY";
		fi
		echo "$varname=\"${!varname}\"" >> peerInfo.temp;
	fi
}

eos_pubkey() {
	varname='EOS_'$np'_PUB'
	if [[ "${!varname}" == "" || $new == true ]]; then
		echo -e " > Peer $np - EOS Public Key: \c"
		read
		if [[ "$REPLY" = "" ]]; then
			echo "Please provide a EOS public key!";
			eos_pubkey;
		else
			declare "$varname"="$REPLY";
		fi
		echo "$varname=\"${!varname}\"" >> peerInfo.temp;
	fi
}

eos_port() {
	varname='EOS_'$np'_P2P'
	if [[ "${!varname}" == "" || $new == true ]]; then
		echo -e " > Peer $np - EOS P2P port: \c"
		read
		if [[ "$REPLY" = "" ]]; then
			echo "Please provide a EOS P2P port!";
			eos_port;
		else
			declare "$varname"="$REPLY";
		fi
		echo "$varname=\"${!varname}\"" >> peerInfo.temp;
	fi
}

new_peer() {
	np=$(cat peerInfo.temp | grep -o "_[0-9]" | sort | uniq | wc -l);
	inc;
	# Wireguard data
	wg_ip;
	wg_pubkey;
	wg_endpoint;
	wg_pka;
	# EOS data
	eos_pubkey;
	eos_port;
	choose_action;
}

check_ip() {
	echo -e "\n Checking for reserved address: $1 ...\n";
	for f in $KBFS_MOUNT/team/eos_ghostbusters/ip_list/*$1; do
		if [ -e "$f" ]; then
			ip_valid=false;
			echo " > !! $1 is not available, please select another";
		else
			ip_valid=true;
			echo -e " > Please inform you producer name (12-char) in order to reserve the address: \c";
			read
			bpname="$REPLY";
			touch "$KBFS_MOUNT/team/eos_ghostbusters/ip_list/$bpname@$1"
			echo " > Address reserved!";
		fi
		break
	done
}

ask_ip() {
	echo
	echo -e " > Wireguard internal IP Address? [range: 192.168.100.0 to 192.168.103.255]: \c"
	read
	WG_INTERFACE="$REPLY";
	check_ip "$WG_INTERFACE"
	if [[ "$ip_valid" == false ]]; then
		ask_ip;
	else
		echo -e "Address = $WG_INTERFACE/22" >> ghostbusters.conf
	fi
}

## Wireguard setup
echo -e " > Do you want to setup Wireguard now? [y/n]: \c"
read
if [[ "$REPLY" = "y" || "$REPLY" = "" ]]; then
	sudo cp /etc/wireguard/ghostbusters.conf ghostbusters.conf.bak
	echo
	echo "Backup saved: ghostbusters.conf.bak";
	umask 077
	wg genkey | tee wg_privatekey.txt | wg pubkey > wg_publickey.txt
	echo
	echo "Your private key is located in the wg_privatekey.txt";
	PVT_KEY=$(cat wg_privatekey.txt);
	PUB_KEY=$(cat wg_publickey.txt);
	echo
	echo "Here is your public key: [$PUB_KEY] ... It was also saved on wg_pubkey.txt for convenience.";
	echo -e "[Interface]\nPrivateKey = $PVT_KEY\nSaveConfig = true\nDNS = 1.1.1.1" > ghostbusters.conf;
	echo
	echo -e " > Please define your Wiregaurd port? [default=5555]: \c"
	read
	WG_PORT="$REPLY";
	if [[ "$WG_PORT" == "" ]]; then
		WG_PORT=5555;
	fi
	echo -e "ListenPort = $WG_PORT" >> ghostbusters.conf;
	ask_ip;
	sudo ip link del dev ghostbusters
	sudo cp ghostbusters.conf /etc/wireguard/.
	sudo wg-quick up ghostbusters

	echo -e "\n\n ------------- CURRENT CONFIGURATION -------------- \n";
	sudo wg show ghostbusters
	echo -e "\n\n -------------------------------------------------- \n";
fi

choose_action;
