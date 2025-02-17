set -e
apt update -y && apt upgrade -y && apt install -y docker-compose-v2 python3 python-is-python3 python3-venv postgresql-client

# Add default ubuntu user to docker group, to allow running docker-compose
gpasswd -a ubuntu docker

cd /home/ubuntu
su ubuntu -c bash -c "python -m venv py_env && source py_env/bin/activate && pip install ansible requests"
