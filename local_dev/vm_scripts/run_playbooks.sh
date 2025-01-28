#!/usr/bin/env bash

source py_env/bin/activate && cd ~/infrastructure/devops \
  && ansible-playbook -i dev.inventory -t postgis_setup core.yml \
  && ansible-playbook -i dev.inventory -t rdflog core.yml \
  && ansible-playbook -i dev.inventory -t restheart_setup core.yml
