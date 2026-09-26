# Jenkins controller with the Docker CLI so it can build images via the host socket.
FROM docker:cli AS dockercli

FROM jenkins/jenkins:lts-jdk17

USER root

COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=dockercli /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins

# Plugins (installed at build time so first boot is fast).
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Configuration as Code.
COPY casc/ /usr/share/jenkins/ref/casc/

USER jenkins
