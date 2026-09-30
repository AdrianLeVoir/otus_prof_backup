# Vagrantfile — стенд hw16 (backup_server + client)
# Приведён для соответствия формату сдачи. Фактически ДЗ выполнено на
# виртуалках Proxmox: backup_server = Hestia (192.168.1.157),
# client = Minerva (192.168.1.201).

MACHINES = {
  :"backup" => { box_name: "ubuntu/jammy64", cpus: 2, memory: 1024, ip: "192.168.57.10" },
  :"client" => { box_name: "ubuntu/jammy64", cpus: 2, memory: 1024, ip: "192.168.57.11" },
}

Vagrant.configure("2") do |config|
  MACHINES.each do |boxname, boxconfig|
    config.vm.synced_folder ".", "/vagrant", disabled: true
    config.vm.network "private_network", ip: boxconfig[:ip]

    config.vm.define boxname do |box|
      box.vm.box = boxconfig[:box_name]
      box.vm.host_name = boxname.to_s
      box.vm.provider "virtualbox" do |v|
        v.memory = boxconfig[:memory]
        v.cpus = boxconfig[:cpus]
      end

      # Настройка ВМ через Ansible
      box.vm.provision "ansible" do |ansible|
        ansible.playbook = "ansible/playbook.yml"
        ansible.groups = {
          "backup" => ["backup"],
          "client" => ["client"],
        }
      end
    end
  end
end
