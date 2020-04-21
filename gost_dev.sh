#! /bin/bash

sh_ver=1.0.1
Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Green_font_prefix}[注意]${Font_color_suffix}"

outinstalltls(){
echo -n "是否自定义ssl证书y/n："
read iftls
if test $iftls = y;then
echo "请输入tls证书地址格式为?cert=/path/to/my/cert/file&key=/path/to/my/key/file："
read tlsaddress
fi
}

installtls(){
echo -n "请问是否验证证书y/n："
read iftls
if test $iftls = y;then
tlsaddress="?secure=true"
fi
}

check_outtls(){
if test $protocol = "tls" -o $protocol = "https" -o $protocol = "wss" -o $protocol = "mwss" -o $protocol = "relay+tls";then
if test $inorout -eq 1;then
installtls
else
outinstalltls
fi
fi
}

installbefore(){
echo -n "请问需要设置多少个本地监听端口？"
read allinstallbeforenum
installbeforenum=1
while test "$installbeforenum" -le "$allinstallbeforenum"
do
echo -n "本地监听端口："
read inport
echo -n "目的地ip（需要被转发ip）："
read ipother
echo -n "需要被转发端口（通常为ssr端口）："
read portother
if test "$installbeforenum" -eq "$allinstallbeforenum";then
if test $protocol = "relay+tls";then
echo "\""udp"://0.0.0.0:"$inport"/"$ipother":"$portother"\"," >> /etc/gost/config.json
fi
echo "\""tcp"://0.0.0.0:"$inport"/"$ipother":"$portother"\"" >> /etc/gost/config.json
else
if test $protocol = "relay+tls";then
echo "\""udp"://0.0.0.0:"$inport"/"$ipother":"$portother"\"," >> /etc/gost/config.json
fi
echo "\""tcp"://0.0.0.0:"$inport"/"$ipother":"$portother"\"," >> /etc/gost/config.json
fi
installbeforenum=$((++installbeforenum))
done
}

installafter(){
echo -n "隧道ip（国外ip）："
read outip
echo -n "隧道出口端口（通信端口）："
read outport
echo -n "隧道出口账户："
read outaccount
echo -n "隧道密码："
read outpassword
}

outinstallafter(){
outip="0.0.0.0"
echo -n "隧道出口端口（通信端口）："
read outport
echo -n "隧道出口账户："
read outaccount
echo -n "隧道密码："
read outpassword
}

installnom(){
echo "\""$protocol"://"$outaccount":"$outpassword"@"$outip":"$outport""$tlsaddress"\"" >> /etc/gost/config.json
}

confstart(){
echo "{
    \"Debug\": true,
    \"Retries\": 0,
    \"ServeNodes\": [" >> /etc/gost/config.json
}

confhalf(){
echo "    ],
    \"ChainNodes\": [" >> /etc/gost/config.json
}

conflast(){
echo "    ]
}" >> /etc/gost/config.json
}

check_inorout(){
echo -n "请问是国内还是国外[1/2]："
read inorout
if test $inorout -eq 1;then
ininstall
else
outinstall
fi
}

check_protocol(){
echo "请问是哪种安装协议 
1 ws    2 tls    3 https    4 http 
5 kcp   6 h2     7 h2c      8 quic 
9 mws   10 wss   11 mwss    12 relay+tls"
echo "----------"
read numprotocol
case "$numprotocol" in
1)
protocol=ws
;;
2)
protocol=tls
;;
3)
protocol=https
;;
4)
protocol=http
;;
5)
protocol=kcp
;;
6)
protocol=h2
;;
7)
protocol=h2c
;;
8)
protocol=quic
;;
9)
protocol=mws
;;
10)
protocol=wss
;;
11)
protocol=mwss
;;
12)
protocol=relay+tls
;;
*)
echo "$protocol is error"
esac
}

outinstall(){
confstart
check_protocol
outinstallafter
check_outtls
installnom
conflast
}

ininstall(){
confstart
check_protocol
installbefore
confhalf
check_outtls
installafter
installnom
conflast
}


checknew(){
checknew=$(gost -V 2>&1|awk '{print $2}')
check_new_ver
echo "你的gost版本为:"$checknew""
echo -n 是否更新\(y/n\)\:
read checknewnum
if test $checknewnum = "y";then
Install_ct
else
exit 0
fi
}

check_sys(){
	if [[ -f /etc/redhat-release ]]; then
		release="centos"
	elif cat /etc/issue | grep -q -E -i "debian"; then
		release="debian"
	elif cat /etc/issue | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
	elif cat /proc/version | grep -q -E -i "debian"; then
		release="debian"
	elif cat /proc/version | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
    fi
	bit=$(uname -m)
        if test "$bit" != "x86_64"; then
           echo "请输入你的芯片架构，/386/armv5/armv6/armv7/armv8"
           read bit
        else bit="amd64"
    fi
}

Installation_dependency(){
	gzip_ver=$(gzip -V)
	if [[ -z ${gzip_ver} ]]; then
		if [[ ${release} == "centos" ]]; then
			yum update
			yum install -y gzip
		else
			apt-get update
			apt-get install -y gzip
		fi
	fi
}

check_root(){
	[[ $EUID != 0 ]] && echo -e "${Error} 当前非ROOT账号(或没有ROOT权限)，无法继续操作，请更换ROOT账号或使用 ${Green_background_prefix}sudo su${Font_color_suffix} 命令获取临时ROOT权限（执行后可能会提示输入当前账号的密码）。" && exit 1
}

check_new_ver(){
ct_new_ver=$(wget --no-check-certificate -qO- -t2 -T3 https://api.github.com/repos/ginuerzh/gost/releases/latest| grep "tag_name"| head -n 1| awk -F ":" '{print $2}'| sed 's/\"//g;s/,//g;s/ //g;s/v//g')
if [[ -z ${ct_new_ver} ]]; then
		echo -e "${Error} gost 最新版本获取失败，请手动获取最新版本号[ https://github.com/ginuerzh/gost/releases ]"
		read -e -p "请输入版本号 [ 格式 x.x.xx , 如 0.8.21 ] :" ct_new_ver
		[[ -z "${ct_new_ver}" ]] && echo "取消..." && exit 1
	else
		echo -e "${Info} gost 目前最新版本为 ${ct_new_ver}"
	fi
}
check_file(){
            if test ! -d "/usr/lib/systemd/system/";then
             `mkdir /usr/lib/systemd/system`
            `chmod -R 777 /usr/lib/systemd/system`
             fi
}
check_nor_file(){
           `rm -rf "$(pwd)"/gost`
             `rm -rf "$(pwd)"/gost.service`
             `rm -rf "$(pwd)"/config.json`
             `rm -rf "$(pwd)"/gost.sh`
             `rm -rf /etc/gost`
             `rm -rf /usr/lib/systemd/system/gost.service`
             `rm -rf /usr/bin/gost`
}

Install_ct(){
           check_root
           check_nor_file
           Installation_dependency
           check_file
           check_sys
           check_new_ver
           `rm -rf gost-linux-"$bit"-"$ct_new_ver".gz`
           `wget --no-check-certificate https://github.com/ginuerzh/gost/releases/download/v"$ct_new_ver"/gost-linux-"$bit"-"$ct_new_ver".gz`
            `gunzip gost-linux-"$bit"-"$ct_new_ver".gz`
            `mv gost-linux-"$bit"-"$ct_new_ver" gost`
            `mv gost /usr/bin/gost`
            `chmod -R 777 /usr/bin/gost`
            `wget --no-check-certificate https://raw.githubusercontent.com/hulisang/Port-forwarding/master/gost.service && chmod -R 777 gost.service && mv gost.service /usr/lib/systemd/system`
            `mkdir /etc/gost && wget --no-check-certificate https://raw.githubusercontent.com/hulisang/Port-forwarding/master/config.json && mv config.json /etc/gost && chmod -R 777 /etc/gost`
            `systemctl enable gost && systemctl restart gost`
            echo "------------------------------"
            if test -a /usr/bin/gost -a /usr/lib/systemctl/gost.service -a /etc/gost/config.json;then
             echo "gost似乎安装成功"
             `rm -rf "$(pwd)"/gost`
             `rm -rf "$(pwd)"/gost.service`
             `rm -rf "$(pwd)"/config.json`
             `rm -rf "$(pwd)"/gost.sh`
            else
            echo "gost没有安装成功"
             `rm -rf   "$(pwd)"/gost`
             `rm -rf "$(pwd)"/gost.service`
             `rm -rf "$(pwd)"/config.json`
             `rm -rf "$(pwd)"/gost.sh`
             fi
}

Uninstall_ct(){
             `rm -rf /usr/bin/gost`
             `rm -rf /usr/lib/systemd/system/gost.service`
             `rm -rf /etc/gost`
             `rm -rf "$(pwd)"/gost.sh`
             echo "gost已经成功删除"
}

Start_ct(){
          `systemctl start gost`
          echo "已启动"
}

Stop_ct(){
          `systemctl stop gost`
            echo "已停止"  
}

Restart_ct(){
            `systemctl restart gost`
             echo "已重启" 
}
    
echo && echo -e "  gost 一键安装脚本 ${Red_font_prefix}[v${sh_ver}]${Font_color_suffix} 更新日期2020/4/21
  ---- ------------------------------ ----
  
 ${Green_font_prefix}1.${Font_color_suffix} 安装 gost
 ${Green_font_prefix}2.${Font_color_suffix} 更新 gost
 ${Green_font_prefix}3.${Font_color_suffix} 卸载 gost
————————————
 ${Green_font_prefix}4.${Font_color_suffix} 启动 gost
 ${Green_font_prefix}5.${Font_color_suffix} 停止 gost
 ${Green_font_prefix}6.${Font_color_suffix} 重启 gost
————————————
 ${Green_font_prefix}7.${Font_color_suffix} 配置gost
 ${Green_font_prefix}8.${Font_color_suffix} 重新配置gost
 ${Green_font_prefix}9.${Font_color_suffix} 输出gost配置
————————————" && echo
read -e -p " 请输入数字 [1-9]:" num
case "$num" in
	1)
	Install_ct
	;;
        2)
        checknew
        ;;
	3)
	Uninstall_ct
	;;
	4)
	Start_ct
	;;
	5)
	Stop_ct
	;;
	6)
	Restart_ct
	;;
        7)
	rm -rf /etc/gost/config.json
        check_inorout
        `systemctl restart gost`
	echo "your json"
	echo "----------"
	cat /etc/gost/config.json
        ;;
        8)
        rm -rf /etc/gost/config.json
	check_inorout
        `chmod -R 777 /etc/gost/config.json`
        `systemctl restart gost`
	echo "your json"
	echo "----------"
	cat /etc/gost/config.json
        ;;
        9)
        cat /etc/gost/config.json
        ;;
	*)
	echo "请输入正确数字 [1-9]"
	;;
esac
