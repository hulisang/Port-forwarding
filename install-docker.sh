function installDocker {
  which docker

  if [ $? -eq 0 ]
  then
      docker --version | grep "Docker version"
      if [ $? -eq 0 ]
      then
          echo "docker existing"
      else
          curl -fsSL https://get.docker.com | bash
      fi
  else
      curl -fsSL https://get.docker.com | bash
  fi
}

installDocker

curl -L "https://github.com/docker/compose/releases/download/latest/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod a+x /usr/local/bin/docker-compose
rm -rf `which dc`
ln -s /usr/local/bin/docker-compose /usr/bin/dc
systemctl start docker.service
systemctl enable docker.service
