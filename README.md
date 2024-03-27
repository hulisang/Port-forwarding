# brook-pf-mod
brook一键端口转发


wget https://raw.githubusercontent.com/hulisang/Port-forwarding/master/brook.sh && chmod +x brook.sh && bash brook.sh


# gost

wget https://raw.githubusercontent.com/hulisang/Port-forwarding/master/gost.sh && chmod +x gost.sh && bash gost.sh


# gost 配置文件版

wget https://raw.githubusercontent.com/hulisang/Port-forwarding/master/gost_dev.sh && chmod +x gost_dev.sh && bash gost_dev.sh


## install docker and docker-compose(dc)

wget https://raw.githubusercontent.com/hulisang/Port-forwarding/master/install-docker.sh && chmod +x install-docker.sh && bash install-docker.sh

# 生成自签证书
wget https://raw.githubusercontent.com/hulisang/Port-forwarding/master/create_self-signed-cert.sh && chmod +x create_self-signed-cert.sh && bash create_self-signed-cert.sh --ssl-domain=www.test.com

--ssl-domain: 生成ssl证书需要的主域名，如不指定则默认为www.rancher.local，如果是ip访问服务，则可忽略；
--ssl-trusted-ip: 一般ssl证书只信任域名的访问请求，有时候需要使用ip去访问server，那么需要给ssl证书添加扩展IP，多个IP用逗号隔开；
--ssl-trusted-domain: 如果想多个域名访问，则添加扩展域名（TRUSTED_DOMAIN）,多个TRUSTED_DOMAIN用逗号隔开；
--ssl-size: ssl加密位数，默认2048；
--ssl-cn: 国家代码(2个字母的代号),默认CN；
使用示例:
./create_self-signed-cert.sh --ssl-domain=www.test.com --ssl-trusted-domain=www.test2.com \
--ssl-trusted-ip=1.1.1.1,2.2.2.2,3.3.3.3 --ssl-size=2048 --ssl-date=3650
