#!/data/data/com.termux/files/usr/bin/bash
# Redire: A script for redirecting Short Message Verification Code and MISSED CALLs to Wechat(via PushPlus)
# Author: Rexoen<https://lod.pub>

token_path=$HOME/.pushplus_token

help_msg(){
echo "A script for redirecting Short Message Verification Code and MISSED CALLs to Wechat(via PushPlus)
By Rexoen<https://lod.pub> UNDER GPL 3.0 Licence

Usage:

$(basename $0) [option] arguments

Options:

-i	--install	install necessary packages and configure server

-t	--token	set a PushPlus token temporarily

-h	--help	show this message
"
}

acquire_permissions(){
	termux-sms-list > /dev/null
	termux-call-log > /dev/null
}

install_pkg(){
	pkg install -y termux-api cronie curl
}

strip_quotes(){
	echo $(sed -e 's/^"//' -e 's/"$//' <<< $1)
}

write_token(){
	received_token=$(termux-dialog -t "PushPlus Token:" | jq)
	code=$(strip_quotes $(jq .code <<< $received_token))
	text=$(strip_quotes $(jq .text <<< $received_token))
	if [ $code != -1 ] || [ -z $text ];then
		echo pls input a valid string..
		write_token
	else
		echo $text >> $token_path
		echo "token($text) has been write to $token_path"
	fi

}

if [ ! -f $token_path ];then
	write_token
fi

token=$(cat $token_path)

make_autolaunch(){
	if [ -d $HOME/.termux/boot ];then
		mkdir -p $HOME/.termux/boot
	fi
	cat > $HOME/.termux/boot/start-crond <<- _EOF
	#!/data/data/com.termux/files/usr/bin/bash
	termux-wake-lock
	crond
	touch /data/data/com.termux/files/usr/tmp/server_launched
	_EOF
	chmod +x $HOME/.termux/boot/start-crond
	if [ $(cat /data/data/com.termux/files/usr/etc/bash.bashrc | tail -n 1 | grep server_launched | wc -l) -eq 0 ];then
		tee -a /data/data/com.termux/files/usr/etc/bash.bashrc <<< "[ -f /data/data/com.termux/files/usr/tmp/server_launched ] || run-parts $HOME/.termux/boot"
	fi
}

SOURCE=$0

configure_cron(){
	LIST=`crontab -l`
	if echo "$LIST" | grep -q "$SOURCE"; then
	   echo "The cron job had already been added before.";
	else
	   crontab -l | { cat; echo "*/1 * * * * $SOURCE"; } | crontab -
	fi
}

function wechat_notify {
	echo "redirecting message via WeChat(PushPlus).."
	curl -X POST -H "Content-Type: application/json" -d '{ "token":"'$token'", "title":"'$1'", "content":"'$2'" }' https://www.pushplus.plus/send/ && termux-notification -t "推送服务" -c "$1$2推送成功" || termux-notification -t "推送服务" -c "!$1$2推送失败"
}
if [ $# -gt 0 ];then
for i in {0..$#};do
	case $1 in
		-i | --install)
			acquire_permissions
			install_pkg
			configure_cron
			make_autolaunch
			continue
			;;
		-t | --token)
			shift
			token=$1
			continue
			;;
		-h | --help)
			help_msg
			continue
			;;
		*)
			help_msg
			;;
	esac
	shift
done
fi

termux-wifi-enable true

if [ ! -d $HOME/.tmp ];then
	mkdir -p $HOME/.tmp
fi

if [ ! -f $HOME/.tmp/smts ];then
	date +%s -u > $HOME/.tmp/smts
fi

prev_smts=$(cat $HOME/.tmp/smts)
# query latest short message
IFS="
"
#iterate last 10 messages for content matching
for sm in $(termux-sms-list | jq -c '.[]');do
	#sm=$(termux-sms-list | jq .[-1])
	# pass readed message.
	if [ $(jq ".read" <<< $sm) == "true" ] || [ $(grep 码 <<< $(jq ".body" <<< $sm) | wc -l) -eq 0 ];then
		continue
	fi
	# parse timestamp and make comparation
	smdt=$(sed -e 's/^"//' -e 's/"$//' <<< $(jq ".received" <<< $sm))
	smts=$(date -d "$smdt" +%s)
	smct=$(jq ".body" <<< $sm)
	smtt=$(grep -ioP "【.+?】" <<< $smct | head -n 1)
	# regex match
	auth_code=$(grep -ioP "[0-9]{4,8}" <<< $(grep -ioE "[^0-9][0-9]{4,8}[^0-9年,\-]" <<< $smct))
	if [ -n "$auth_code" ];then
		if (( $smts > $prev_smts ));then
			echo redirecting message!
			echo $smtt
			echo $auth_code
			wechat_notify $smtt $auth_code
			echo $smts > $HOME/.tmp/smts
		fi
	fi
done

latest_call_log=$(termux-call-log | jq -c .[])

if [ ! -f $HOME/.tmp/clts ];then
	date +%s -u > $HOME/.tmp/clts
fi

prev_clts=$(cat $HOME/.tmp/clts)

for i in $latest_call_log;do
	if [ $(sed -e 's/^"//' -e 's/"$//' <<< $(jq '.type' <<< $i)) != "MISSED" ];then
		continue
	fi
	cldt=$(sed -e 's/^"//' -e 's/"$//' <<< $(jq ".date" <<< $i))
	clts=$(date -d "$cldt" +%s)
	if (( $clts > $prev_clts ));then
		number=$(sed -e 's/^"//' -e 's/"$//' <<< $(jq '.phone_number' <<< $i))
		echo $number
		wechat_notify "未接来电" "号码:$number \n时间:$cldt"
		echo $clts > $HOME/.tmp/clts
	fi
done
