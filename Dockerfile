FROM ocaml/opam:debian-11-ocaml-4.13 AS build
RUN sudo ln -f /usr/bin/opam-2.1 /usr/bin/opam && opam update
RUN sudo apt-get update && sudo apt-get install libev-dev capnproto graphviz m4 pkg-config libsqlite3-dev libgmp-dev -y --no-install-recommends
RUN cd ~/opam-repository && git pull origin master && git reset --hard 4e58a1f2b141f380f30610741dab58d0ea53c52a && opam update
COPY --chown=opam \
	vendor/ocurrent/current_docker.opam \
	vendor/ocurrent/current_github.opam \
	vendor/ocurrent/current_gitlab.opam \
	vendor/ocurrent/current_git.opam \
	vendor/ocurrent/current.opam \
	vendor/ocurrent/current_rpc.opam \
	vendor/ocurrent/current_slack.opam \
	vendor/ocurrent/current_web.opam \
	/src/vendor/ocurrent/
COPY --chown=opam \
	vendor/ocluster/ocluster-api.opam \
	vendor/ocluster/current_ocluster.opam \
	/src/vendor/ocluster/
COPY --chown=opam \
	vendor/current-web-pipelines/current-web-pipelines.opam \
	/src/vendor/current-web-pipelines/
WORKDIR /src
RUN opam pin add -yn current_docker.dev "./vendor/ocurrent" && \
    opam pin add -yn current_github.dev "./vendor/ocurrent" && \
    opam pin add -yn current_gitlab.dev "./vendor/ocurrent" && \
    opam pin add -yn current_git.dev "./vendor/ocurrent" && \
    opam pin add -yn current.dev "./vendor/ocurrent" && \
    opam pin add -yn current_rpc.dev "./vendor/ocurrent" && \
    opam pin add -yn current_slack.dev "./vendor/ocurrent" && \
    opam pin add -yn current_web.dev "./vendor/ocurrent" && \
    opam pin add -yn current_ocluster.dev "./vendor/ocluster" && \
    opam pin add -yn ocluster-api.dev "./vendor/ocluster" && \
    opam pin add -yn current-web-pipelines.dev "./vendor/current-web-pipelines"
COPY --chown=opam tezos-ci.opam /src/
RUN opam install -y --deps-only .
ADD --chown=opam . .
RUN opam exec -- dune build ./_build/install/default/bin/tezos-ci

FROM debian:11
RUN apt-get update && apt-get install libev4 openssh-client curl gnupg2 dumb-init git graphviz libsqlite3-dev ca-certificates netbase -y --no-install-recommends
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
RUN echo 'deb [arch=amd64] https://download.docker.com/linux/debian bullseye stable' >> /etc/apt/sources.list
RUN apt-get update && apt-get install docker-ce -y --no-install-recommends
WORKDIR /var/lib/ocurrent
ENTRYPOINT ["dumb-init", "/usr/local/bin/tezos-ci"]
ENV OCAMLRUNPARAM=a=2
# Enable experimental for docker manifest support
ENV DOCKER_CLI_EXPERIMENTAL=enabled
COPY --from=build /src/_build/install/default/bin/tezos-ci /usr/local/bin/
