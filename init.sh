#!/bin/bash
set -e

SCRIPT="$(readlink -f "$0")"
SCRIPT_PATH="$(dirname $SCRIPT)"
pushd $SCRIPT_PATH || exit 1

#启用自建的一些方便函数
. $SCRIPT_PATH/work/tools/functions.sh

if ! HasRootPremission; then
    if IsCommandExists sudo; then
        sudo bash "$0"
        exit $?
    else
        ray_echo_Red "ERROR: You need to be root to run this script"
    fi
fi

if ! IsFile .env; then
    cp .env.sample .env;
    ray_echo_Red "please modify .env first!";
    exit 1
fi

#国内知名的仓库源
mirrors=(
        #阿里公网
        mirrors.aliyun.com
        #阿里内网
        mirrors.cloud.aliyuncs.com
        #腾讯公网
        mirrors.tencentyun.com
        #腾讯内网
        mirrors.cloud.tencent.com
    )

#因为我司服务器都是在aliyun上，所以优先使用aliyun的内部网络
mirrors_default=${mirrors[1]}

if ! IsCommandExists docker; then
    if IsUbuntu; then
        # cp /etc/apt/sources.list /etc/apt/sources.list.bak
        if ! apt-key fingerprint 0EBFCD88 2>/dev/null | grep -q 'docker@docker.com'; then
            apt-get update -y
            apt-get remove docker docker-engine docker.io containerd runc -y
            apt-get install apt-transport-https ca-certificates curl gnupg-agent \
                software-properties-common -y

            curl -fsSL https://${mirrors[0]}/docker-ce/linux/ubuntu/gpg | apt-key add -
            add-apt-repository \
            "deb [arch=amd64 trusted=yes] http://${mirrors_default}/docker-ce/linux/ubuntu $(lsb_release -cs)  stable"
        fi

        InstallApps docker-ce docker-ce-cli containerd.io  mysql-client-core-5.7 jq git htop iftop
    elif IsRedHat; then
        mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup
        wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
        mv /etc/yum.repos.d/epel.repo /etc/yum.repos.d/epel.repo.backup
        wget -O /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo

        yum makecache -y
        yum remove docker docker-client docker-client-latest docker-common \
            docker-latest docker-latest-logrotate docker-logrotate docker-engine -y
        yum install -y yum-utils device-mapper-persistent-data lvm2
        yum-config-manager --add-repo https://${mirrors_default}/docker-ce/linux/centos/docker-ce.repo

        InstallApps docker-ce docker-ce-cli containerd.io  mysql-client-core-5.7 jq git htop iftop
    fi

    if ! IsFile /usr/local/bin/docker-compose; then
        curl -fsSL https://get.daocloud.io/docker/compose/releases/download/1.24.1/docker-compose-$(uname -s)-$(uname -m) \
            -o /usr/local/bin/docker-compose  && chmod +x /usr/local/bin/docker-compose

        if ! IsSameStr "$(sha256sum /usr/local/bin/docker-compose | awk '{print $1 }')"  \
                       "cfb3439956216b1248308141f7193776fcf4b9c9b49cbbe2fb07885678e2bb8a" ; then
            ray_echo_Red "docker-compose 文件sha256不对"
            exit 1
        fi
    fi
fi

#注入公用的docker-compose环境变量
. .env


if ! IsFileHasStr '#lnmp-tools' $HOME/.bashrc; then
    sed -i -e "\$a#lnmp-tools\n. $SCRIPT_PATH/work/tools/functions.sh\n" $HOME/.bashrc
fi

if IsDir /etc/logrotate.d; then
    cat > /etc/logrotate.d/wwwlogs <<EOF
$SCRIPT_PATH/work/logs/*.log {
    su root root
    daily
    rotate 7
    missingok
    notifempty
    compress
    dateext
    sharedscripts
    postrotate
         /usr/bin/env docker exec nginx nginx -s reopen
    endscript
}
EOF
    chmod 644 /etc/logrotate.d/wwwlogs
fi

docker-compose down --rmi local 2>/dev/null || true

if ! IsFile db_root_password.txt; then

    DB_ROOT_PASSWD="$(MakePassword)"
    DB_DEFAULT_PASSWD="$(MakePassword)"

    echo -n "$DB_ROOT_PASSWD" > db_root_password.txt
    echo -n "$DB_DEFAULT_PASSWD" > db_${MYSQL_USER}_password.txt

    chmod 400 db_root_password.txt
    chmod 444 db_${MYSQL_USER}_password.txt
fi

find $SCRIPT_PATH -type f -exec chmod 644 {} \;
find $SCRIPT_PATH -name "*.sh" -exec chmod 755 {} \;
find $SCRIPT_PATH -type d  -exec chmod 755 {} \;
chmod 777 work/logs

docker-compose up -d

rm -f "$SCRIPT"

popd