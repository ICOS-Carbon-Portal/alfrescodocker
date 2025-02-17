# Local development support services

The contents of this directory serves as executable documentation for running the required services in order to do local development of the [meta](https://github.com/ICOS-Carbon-Portal/meta) and [data](https://github.com/ICOS-Carbon-Portal/data) services.
The main goal is getting things up-and-running quickly, while more detailed documentation can be found in the main [README](https://github.com/ICOS-Carbon-Portal/infrastructure) of this repository.

The main entry point is [this justfile](./justfile) and the support services are run in an LXD container.
Before you get started, install these tools.

### Tools needed:
- [just](https://github.com/casey/just)
- [LXD/LXC](https://ubuntu.com/server/docs/lxd-containers)

### Manual preparation
- Create a `.vault_password` file in this directory, with contents given to you by a colleague.
- Minimal configs for [data](https://github.com/ICOS-Carbon-Portal/data)  and [meta](https://github.com/ICOS-Carbon-Portal/meta)  services can be found in [example_configs](./example_configs). Copy the contents of these to `application.conf` in respective repository.

### Running
You should now be able to run:
```
just create-vm run-playbooks
```
If this succeeds, an LXC container with the required services should now be running, and you should be able to run both the `meta` and `data` services.

### Development/Testing

When working on the `ansible` roles in this repository, the quickest way to test the results is to run
```
just init-vm run-playbooks
```
The task `init-vm` will use a snapshot of the LXC container in order to skip most of the setup, and copy the local state of this repository into the container.
If there are errors in the edited playbooks, it is best to simply run `just run-playbooks` until they work, rather than `init-vm` every time.

To start the container completely from scratch, use `just reset-vm` or `just destroy-vm`.
