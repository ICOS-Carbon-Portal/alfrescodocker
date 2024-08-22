import logging
import os

from dockerspawner import SystemUserSpawner


# CUSTOM SPAWNER
class CustomDockerSpawner(SystemUserSpawner):
    user_volumes = {{ conf.user_volumes }}

    def start(self):
        self.volumes.update(self.user_volumes.get(self.user.name, {}))
        return super().start()

c.JupyterHub.spawner_class = CustomDockerSpawner


# DEBUGGING
# Makes the hub really spammy.
# c.JupyterHub.log_level = logging.DEBUG
# c.DockerSpawner.debug = True

# Workaround to allow usernames with '-' in them.
c.DockerSpawner.escape = 'legacy'


# CONFIGURATION OF THE HUB
# The ip address for the Hub process to *bind* to.
c.JupyterHub.hub_ip = '0.0.0.0'
c.JupyterHub.cleanup_servers = False
c.JupyterHub.template_paths = ["/srv/jupyterhub/templates"]

# We handle authentication in the reverse proxy
c.JupyterHub.authenticate_prometheus = False


# XSRF
# <2024-08-16 Fri>
# After upgrading to jupyterhub 5.1 (from version 3), we get these errors:
# "HTTP 403: Forbidden ('_xsrf' argument missing from GET)"

# The are quite a number of bug reports about this, including some about the
# disable_check_xsrf setting not working.

# This setting keeps popping up, but doesn't seem to do anything.
# c.JupyterHub.disable_check_xsrf = True

# Neither does this
# c.Authenticator.disable_check_xsrf = True

# This however, works!
# FIXME: xsrf really shouldn't be disabled
c.JupyterHub.tornado_settings = {
    'xsrf_cookies': False,
    'check_xsrf_cookie': False,
}


# c.JupyterHub.allow_named_servers = True
# c.JupyterHub.named_server_limit_per_user = 5

{% if conf.mem_limit is defined %}
# Maximum number of bytes a single-user notebook server is allowed to use.
c.Spawner.mem_limit = '{{ conf.mem_limit }}'
{% endif %}

{% if conf.cpu_limit is defined %}
# Maximum number of cpu-cores a single-user notebook server is allowed to use.
c.Spawner.cpu_limit = {{ conf.cpu_limit }}
{% endif %}

# CONFIGURATION OF THE PROXY
# We're not starting the proxy, it's a separate docker-compose service.
c.ConfigurableHTTPProxy.should_start = False
c.ConfigurableHTTPProxy.api_url = 'http://proxy:8001'

# The host name that notebooks will use to connect to the hub. In our case,
# this is assigned to the hub image by docker-compose.
c.JupyterHub.hub_connect_ip = 'hub'


# USER MANAGEMENT
c.JupyterHub.admin_access = True
c.Authenticator.allow_all = True
c.Authenticator.admin_users = set({{ conf.admin_users }})

# CONFIGURATION OF THE NOTEBOOK CONTAINERS
c.DockerSpawner.network_name = os.environ.get("NETWORK_NAME", "jupyter")

# Remove containers when they're shut down. Since we're using bind-mounted home
# directories, we won't lose any data and without this option it's very hard to
# introduce new images (since the containers are just stopped and thus uses the
# old image).
c.DockerSpawner.remove = True

c.DockerSpawner.use_internal_hostname = True
c.DockerSpawner.image = os.environ.get("NOTEBOOK_IMAGE", "{{ conf.image }}")
c.DockerSpawner.notebook_dir = '/home/{username}'
c.DockerSpawner.read_only_volumes = {
    '/etc/shadow'    : '/etc/shadow',
    '/etc/group'     : '/etc/group',
    '/etc/gshadow'   : '/etc/gshadow',
    '/etc/passwd'    : '/etc/passwd',
    '/data'          : '/data'
}

c.DockerSpawner.volumes = {'/project': '/project'}

{% if conf.allowed_images is defined %}
c.DockerSpawner.allowed_images = {{ conf.allowed_images }}
{% endif %}

# https://github.com/jupyterhub/dockerspawner/commit/83c4770c17a8fbd1e2f8f42068552937c5ff0eee
# This commits changes the default behaviour from run-as-root to
# run-as-user. However, this new behaviour does not set supplementary groups
# properly (maybe we need some other kind of config for that?), so we revert
# back to running as root. The notebook will then switch to the correct
# user/group based on NB_USER and NB_GROUP.
c.DockerSpawner.run_as_root = True

# The override configuration file doesn't have to exist.
load_subconfig(os.path.join(os.path.dirname(__file__),
                            'jupyterhub_config_override.py'))
