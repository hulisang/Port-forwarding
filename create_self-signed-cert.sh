#!/bin/bash

help ()
{
    echo  ' ================================================================ '
    echo  ' --ssl-domain: 生成ssl证书需要的主域名，如不指定则默认为www.rancher.local，如果是ip访问服务，则可忽略；'
    echo  ' --ssl-trusted-ip: 一般ssl证书只信任域名的访问请求，有时候需要使用ip去访问server，那么需要给ssl证书添加扩展IP，多个IP用逗号隔开；'
    echo  ' --ssl-trusted-domain: 如果想多个域名访问，则添加扩展域名（SSL_TRUSTED_DOMAIN）,多个扩展域名用逗号隔开；'
    echo  ' --ssl-size: ssl加密位数，默认2048；'
    echo  ' --ssl-cn: 国家代码(2个字母的代号),默认CN;'
    echo  ' --ca-cert-recreate: 是否重新创建 ca-cert，ca 证书默认有效期 10 年，创建的 ssl 证书有效期如果是一年需要续签，那么可以直接复用原来的 ca 证书，默认 false;'
    echo  ' 使用示例:'
    echo  ' ./create_self-signed-cert.sh --ssl-domain=www.test.com --ssl-trusted-domain=www.test2.com \ '
    echo  ' --ssl-trusted-ip=1.1.1.1,2.2.2.2,3.3.3.3 --ssl-size=2048 --ssl-date=3650'
    echo  ' ================================================================'
}

case "$1" in
    -h|--help) help; exit;;
esac

if [[ $1 == '' ]];then
    help;
    exit;
fi

CMDOPTS="$*"
for OPTS in $CMDOPTS;
do
    key=$(echo ${OPTS} | awk -F"=" '{print $1}' )
    value=$(echo ${OPTS} | awk -F"=" '{print $2}' )
    case "$key" in
        --ssl-domain) SSL_DOMAIN=$value ;;
        --ssl-trusted-ip) SSL_TRUSTED_IP=$value ;;
        --ssl-trusted-domain) SSL_TRUSTED_DOMAIN=$value ;;
        --ssl-size) SSL_SIZE=$value ;;
        --ssl-date) SSL_DATE=$value ;;
        --ca-date) CA_DATE=$value ;;
        --ssl-cn) CN=$value ;;
        --ca-cert-recreate) CA_CERT_RECREATE=$value ;;
        --ca-key-recreate) CA_KEY_RECREATE=$value ;;
    esac
done

# CA相关配置
CA_KEY_RECREATE=${CA_KEY_RECREATE:-false}
CA_CERT_RECREATE=${CA_CERT_RECREATE:-false}

CA_DATE=${CA_DATE:-3650}
CA_KEY=${CA_KEY:-cakey.pem}
CA_CERT=${CA_CERT:-cacerts.pem}
CA_DOMAIN=cattle-ca

# ssl相关配置
SSL_CONFIG=${SSL_CONFIG:-$PWD/openssl.cnf}
SSL_DOMAIN=${SSL_DOMAIN:-'www.rancher.local'}
SSL_DATE=${SSL_DATE:-3650}
SSL_SIZE=${SSL_SIZE:-2048}

## 国家代码(2个字母的代号),默认CN;
CN=${CN:-CN}

SSL_KEY=$SSL_DOMAIN.key
SSL_CSR=$SSL_DOMAIN.csr
SSL_CERT=$SSL_DOMAIN.crt

echo -e "\033[32m ---------------------------- \033[0m"
echo -e "\033[32m       | 生成 SSL Cert |       \033[0m"
echo -e "\033[32m ---------------------------- \033[0m"

# 如果存在 ca-key， 并且需要重新创建 ca-key
if [[ -e ./${CA_KEY} ]] && [[ ${CA_KEY_RECREATE} == 'true' ]]; then

    # 先备份旧 ca-key，然后重新创建 ca-key
    echo -e "\033[32m ====> 1. 发现已存在 CA 私钥，备份 "${CA_KEY}" 为 "${CA_KEY}"-bak，然后重新创建 \033[0m"
    mv ${CA_KEY} "${CA_KEY}"-bak-$(date +"%Y%m%d%H%M")
    openssl genrsa -out ${CA_KEY} ${SSL_SIZE}

    # 如果存在 ca-cert，因为 ca-key 重新创建，则需要重新创建 ca-cert。先备份然后重新创建 ca-cert
    if [[ -e ./${CA_CERT} ]]; then
        echo -e "\033[32m ====> 2. 发现已存在 CA 证书，先备份 "${CA_CERT}" 为 "${CA_CERT}"-bak，然后重新创建 \033[0m"
        mv ${CA_CERT} "${CA_CERT}"-bak-$(date +"%Y%m%d%H%M")
        openssl req -x509 -sha256 -new -nodes -key ${CA_KEY} -days ${CA_DATE} -out ${CA_CERT} -subj "/C=${CN}/CN=${CA_DOMAIN}"
    else
        # 如果不存在 ca-cert，直接创建 ca-cert
        echo -e "\033[32m ====> 2. 生成新的 CA 证书 ${CA_CERT} \033[0m"
        openssl req -x509 -sha256 -new -nodes -key ${CA_KEY} -days ${CA_DATE} -out ${CA_CERT} -subj "/C=${CN}/CN=${CA_DOMAIN}"
    fi

# 如果存在 ca-key，并且不需要重新创建 ca-key
elif [[ -e ./${CA_KEY} ]] && [[ ${CA_KEY_RECREATE} == 'false' ]]; then

    # 存在旧 ca-key，不需要重新创建，直接复用
    echo -e "\033[32m ====> 1. 发现已存在 CA 私钥，直接复用 CA 私钥 "${CA_KEY}" \033[0m"

    # 如果存在 ca-cert，并且需要重新创建 ca-cert。先备份然后重新创建
    if [[ -e ./${CA_CERT} ]] && [[ ${CA_CERT_RECREATE} == 'true' ]]; then
        echo -e "\033[32m ====> 2. 发现已存在 CA 证书，先备份 "${CA_CERT}" 为 "${CA_CERT}"-bak，然后重新创建 \033[0m"
        mv ${CA_CERT} "${CA_CERT}"-bak-$(date +"%Y%m%d%H%M")
        openssl req -x509 -sha256 -new -nodes -key ${CA_KEY} -days ${CA_DATE} -out ${CA_CERT} -subj "/C=${CN}/CN=${CA_DOMAIN}"

    # 如果存在 ca-cert，并且不需要重新创建 ca-cert，直接复用
    elif [[ -e ./${CA_CERT} ]] && [[ ${CA_CERT_RECREATE} == 'false' ]]; then
        echo -e "\033[32m ====> 2. 发现已存在 CA 证书，直接复用 CA 证书 "${CA_CERT}" \033[0m"
    else
        # 如果不存在 ca-cert ，直接创建 ca-cert
        echo -e "\033[32m ====> 2. 生成新的 CA 证书 ${CA_CERT} \033[0m"
        openssl req -x509 -sha256 -new -nodes -key ${CA_KEY} -days ${CA_DATE} -out ${CA_CERT} -subj "/C=${CN}/CN=${CA_DOMAIN}"
    fi

# 如果不存在 ca-key
else
    # ca-key 不存在，直接生成
    echo -e "\033[32m ====> 1. 生成新的 CA 私钥 ${CA_KEY} \033[0m"
    openssl genrsa -out ${CA_KEY} ${SSL_SIZE}

    # 如果存在旧的 ca-cert，先做备份，然后重新生成 ca-cert
    if [[ -e ./${CA_CERT} ]]; then
        echo -e "\033[32m ====> 2. 发现已存在 CA 证书，先备份 "${CA_CERT}" 为 "${CA_CERT}"-bak，然后重新创建 \033[0m"
        mv ${CA_CERT} "${CA_CERT}"-bak-$(date +"%Y%m%d%H%M")
        openssl req -x509 -sha256 -new -nodes -key ${CA_KEY} -days ${CA_DATE} -out ${CA_CERT} -subj "/C=${CN}/CN=${CA_DOMAIN}"
    else
        # 不存在旧的 ca-cert，直接生成 ca-cert
        echo -e "\033[32m ====> 2. 生成新的 CA 证书 ${CA_CERT} \033[0m"
        openssl req -x509 -sha256 -new -nodes -key ${CA_KEY} -days ${CA_DATE} -out ${CA_CERT} -subj "/C=${CN}/CN=${CA_DOMAIN}"
    fi

fi

echo -e "\033[32m ====> 3. 生成 Openssl 配置文件 ${SSL_CONFIG} \033[0m"
cat > ${SSL_CONFIG} <<EOM
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, serverAuth
EOM

if [[ -n ${SSL_TRUSTED_IP} || -n ${SSL_TRUSTED_DOMAIN} || -n ${SSL_DOMAIN} ]]; then
    cat >> ${SSL_CONFIG} <<EOM
subjectAltName = @alt_names
[alt_names]
EOM
    IFS=","
    dns=(${SSL_TRUSTED_DOMAIN})
    dns+=(${SSL_DOMAIN})
    for i in "${!dns[@]}"; do
      echo DNS.$((i+1)) = ${dns[$i]} >> ${SSL_CONFIG}
    done

    if [[ -n ${SSL_TRUSTED_IP} ]]; then
        ip=(${SSL_TRUSTED_IP})
        for i in "${!ip[@]}"; do
          echo IP.$((i+1)) = ${ip[$i]} >> ${SSL_CONFIG}
        done
    fi
fi

echo -e "\033[32m ====> 4. 生成服务 SSL KEY ${SSL_KEY} \033[0m"
openssl genrsa -out ${SSL_KEY} ${SSL_SIZE}

echo -e "\033[32m ====> 5. 生成服务 SSL CSR ${SSL_CSR} \033[0m"
openssl req -sha256 -new -key ${SSL_KEY} -out ${SSL_CSR} -subj "/C=${CN}/CN=${SSL_DOMAIN}" -config ${SSL_CONFIG}

echo -e "\033[32m ====> 6. 生成服务 SSL CERT ${SSL_CERT} \033[0m"
openssl x509 -sha256 -req -in ${SSL_CSR} -CA ${CA_CERT} \
    -CAkey ${CA_KEY} -CAcreateserial -out ${SSL_CERT} \
    -days ${SSL_DATE} -extensions v3_req \
    -extfile ${SSL_CONFIG}

echo -e "\033[32m ====> 7. 证书制作完成 \033[0m"
echo
echo -e "\033[32m ====> 8. 以 YAML 格式输出结果 \033[0m"
echo "----------------------------------------------------------"
echo "ca_key: |"
cat $CA_KEY | sed 's/^/  /'
echo
echo "ca_cert: |"
cat $CA_CERT | sed 's/^/  /'
echo
echo "ssl_key: |"
cat $SSL_KEY | sed 's/^/  /'
echo
echo "ssl_csr: |"
cat $SSL_CSR | sed 's/^/  /'
echo
echo "ssl_cert: |"
cat $SSL_CERT | sed 's/^/  /'
echo

echo -e "\033[32m ====> 9. 附加 CA 证书到 Cert 文件 \033[0m"
cat ${CA_CERT} >> ${SSL_CERT}
echo "ssl_cert: |"
cat $SSL_CERT | sed 's/^/  /'
echo

echo -e "\033[32m ====> 10. 重命名服务证书 \033[0m"
echo "cp ${SSL_DOMAIN}.key tls.key"
cp ${SSL_DOMAIN}.key tls.key
echo "cp ${SSL_DOMAIN}.crt tls.crt"
cp ${SSL_DOMAIN}.crt tls.crt
