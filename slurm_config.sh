#! /bin/bash

echo y | sudo apt-get update
echo y | sudo apt-get upgrade
cluster_config=/etc/hosts
jug=0
cnt=0
configToNode=""
while read line
do
	if [ "$jug" -eq 1 ] 
	then
		let cnt++
		if [ "$line" == "###" ]
		then
			configToNode=$(printf "${configToNode}\n${line}")
			break
		fi
		configToNode=$(printf "${configToNode}\n${line}")
		echo -e "${configToNode}"
	fi
	if [ "$line" == "###" ] 
	then
		let jug=1
		configToNode=$(printf "${configToNode}${line}\n")
		echo -e "${configToNode}"
	fi
done < $cluster_config
echo " "
echo -e "${configToNode}" > output.txt

cnt=0
declare -A cluster
while read line
do
	if [ "$line" != "###" ]
	then
		arg=$(echo $line | cut -d ' ' -f 2)
		if [ "$cnt" -gt 0 ]
		then
            cluster["${cnt}"]="${arg}"
			scp ./output.txt ${arg}:/root/
			ssh root@node1${arg} "cat ./output.txt >> /etc/hosts"
		fi
		let cnt++
	fi
done < output.txt

##
echo y | sudo apt-get install munge
echo y | create-munge-key
chmod 700 /etc/munge
chmod 700 /var/lib/munge
chmod 700 /var/log/munge
chmod 755 /run/munge
systemctl daemon-reload
systemctl restart munge.service

for i in ${cluster[@]}
do
    ssh root@${i} << remotessh
    echo y | sudo apt-get update
    echo y | sudo apt-get upgrade
    echo y | sudo apt-get install munge
    chmod 700 /etc/munge
    chmod 700 /var/lib/munge
    chmod 700 /var/log/munge
    chmod 755 /run/munge
    exit
remotessh
    scp /etc/munge/munge.key root@${i}:/etc/munge/
    ssh root@node1 << remotessh
    systemctl daemon-reload
    systemctl restart munge.service
    exit
remotessh
done
##

curl -JLO https://download.schedmd.com/slurm/slurm-22.05.9.tar.bz2
tar -jxvf slurm-22.05.9.tar.bz2
sudo apt-get install make hwloc libhwloc-dev libmunge-dev libmunge2 munge  libmysqlclient-dev -y
cd ./slurm-22.05.9
./configure
make -j4
make install

for i in ${cluster[@]}
do
    ssh root@${i} << remotessh
    curl -JLO https://download.schedmd.com/slurm/slurm-22.05.9.tar.bz2
    tar -jxvf slurm-22.05.9.tar.bz2
    sudo apt-get install make hwloc libhwloc-dev libmunge-dev libmunge2 munge mariadb-server libmysqlclient-dev -y
    cd ./slurm-22.05.9
    ./configure
    make -j4
    make install
    exit
remotessh
done

useradd slurm
sudo mkdir /var/spool/slurm
sudo chown -R slurm.slurm /var/spool/slurm
sudo mkdir /var/run/slurm/
sudo chown -R slurm.slurm /var/run/slurm/
sudo mkdir /var/log/slurm/
cd ~/slurm-22.05.9/etc
cp slurm*.service /etc/systemd/system
cp ./slurm.conf /usr/local/etc/
cp ./slurmdbd.conf /usr/local/etc/

for i in ${cluster[@]}
do
    scp ./slurm.conf root@${i}:/usr/local/etc/ 
    ssh root@${i} << remotessh
    useradd slurm
    sudo mkdir /var/spool/slurm
    sudo chown -R slurm.slurm /var/spool/slurm
    sudo mkdir /var/run/slurm/
    sudo chown -R slurm.slurm /var/run/slurm/
    sudo mkdir /var/log/slurm/
    cd ~/slurm-22.05.9/etc
    cp slurm*.ervice /etc/systemd/system
    exit
remotessh
done

systemctl daemon-reload
systemctl start slurmctld
systemctl start slurmd
systemctl start slurmdbd

for i in ${cluster[@]}
do
    ssh root@${i} << remotessh
    systemctl daemon-reload
    systemctl start slurmd
    exit
remotessh
done