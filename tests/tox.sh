#!/bin/bash -ex

# Proxy script from tox. This is an intermediate script so that we can setup
# the environment properly then call ceph-ansible for testing, and finally tear
# down, while keeping tox features of simplicity

# setup
#################################################################################
sudo apt-get install -y --force-yes docker.io
sudo apt-get install -y --force-yes xfsprogs
git clone -b $CEPH_ANSIBLE_BRANCH --single-branch https://github.com/ceph/ceph-ansible.git ceph-ansible
pip install -r $TOXINIDIR/ceph-ansible/tests/requirements.txt

# pull requests tests should never have these directories here, but branches
# do, so for the build scripts to work correctly, these neeed to be removed
# XXX It requires sudo because these will appear with `root` ownership
sudo rm -rf "$WORKSPACE"/{daemon,demo,base}

sudo "$WORKSPACE"/travis-builds/purge_cluster.sh
# XXX purge_cluster only stops containers, it doesn't really remove them so try to
# remove them for real
containers_to_remove=$(sudo docker ps -a -q)

if [ "${containers_to_remove}" ]; then
    sudo docker rm -f $@ ${containers_to_remove} || echo failed to remove containers
fi

sudo "$WORKSPACE"/travis-builds/build_imgs.sh

# test
#################################################################################

# TODO: get the output image from build_imgs.sh to pass onto ceph-ansible

# vars
#################################################################################
ANSIBLE_SSH_ARGS = -F $CEPH_ANSIBLE_SCENARIO_PATH/vagrant_ssh_config
ANSIBLE_ACTION_PLUGINS = $TOXINIDIR/plugins/actions
# only available for ansible >= 2.2
ANSIBLE_STDOUT_CALLBACK = debug

# run vagrant and ceph-ansible tests
#################################################################################
cd "$CEPH_ANSIBLE_SCENARIO_PATH"
vagrant up --no-provision --provider=$VAGRANT_PROVIDER
bash $TOXINIDIR/tests/scripts/generate_ssh_config.sh $CEPH_ANSIBLE_SCENARIO_PATH

ansible-playbook -vv -i $CEPH_ANSIBLE_SCENARIO_PATH/hosts $TOXINIDIR/site-docker.yml.sample --extra-vars="fetch_directory=$CEPH_ANSIBLE_SCENARIO_PATH/fetch"

ansible-playbook -vv -i $CEPH_ANSIBLE_SCENARIO_PATH/hosts $TOXINIDIR/tests/functional/setup.yml

testinfra -n 4 --sudo -v --connection=ansible --ansible-inventory=$CEPH_ANSIBLE_SCENARIO_PATH/hosts $TOXINIDIR/tests/functional/tests


# teardown
#################################################################################
vagrant destroy --force
