SHELL = bash
TIMESTAMP = $(shell date +%s)

test:
	drone exec

ssh:
	@docker run -ti --rm -u ubuntu -w /home/ubuntu -v $(DATA):/data -v /var/run/docker.sock:/var/run/docker.sock imma/ubuntu:base bash || true

docker-vm:
	@docker run -it --privileged --pid=host imma/ubuntu:base nsenter -t 1 -m -u -n -i sh || true

init:
	$(MAKE) up
	$(MAKE) tx-init

up:
	mkdir -p b/devshell/.ssh/
	rsync -ia .ssh/authorized_keys b/devshell/.ssh/
	docker-compose down
	docker-compose up -d --force-recreate --build

tx-init:
	tx init $(shell docker-compose ps -q shell).docker

tx:
	tx $(shell docker-compose ps -q shell).docker

down:
	docker-compose down

cache:
	source work/ubuntu-config/script/profile && source work/block/script/profile && require && block gen profile > .bashrc.cache.1
	mv -f .bashrc.cache.1 .bashrc.cache

sync:
	block sync fast
	$(MAKE) cache

update-modules:
	block list | awk '/\/work\// {print $$3, $$2}' | perl -pe 's{[^\s]+?/work/}{work/}' | grep -v 'work/ubuntu' | runmany 1 2 'git update-index --cacheinfo 160000 $$(cd $(BLOCK_PATH)/../$$2 && git rev-parse HEAD) $$2'

lock:
	$(MAKE) update-modules || true
	block lock
	git add -u work Blockfile.lock Blockfile.json
	git add .public content
	gs

dummy:
	[[ "$(shell uname -s)" == "Darwin" ]] && sudo ifconfig lo0 alias 169.254.1.1 255.255.255.255 2>/dev/null || true

shell: dummy
	cd docker/shell && env COMPOSE_PROJECT_NAME=$(TIMESTAMP) $(MAKE)

base: dummy
	runmany 'docker rmi imma/ubuntu:$$1 || true' base latest rebase1 base1
	docker system prune -f || true
	docker system prune -f || true
	docker system prune -f || true
	rm -f $(DATA)/cache/git/$(PKGSRC_BRANCH).tar.gz
	cd docker/base && $(MAKE)

rebase: dummy
	cd docker/rebase && env COMPOSE_PROJECT_NAME=$(TIMESTAMP) $(MAKE)

push:
	docker push imma/ubuntu:shell
	docker push imma/ubuntu:base
	docker push imma/ubuntu:latest

pull:
	docker pull imma/ubuntu:shell
	docker pull imma/ubuntu:base
	docker pull imma/ubuntu:latest

docs:
	mkdir -p content
	runmany 'cd $$1 && block compile docs' . work/{block,runmany}
	ln -nfs $(shell cd .public && ls -d ../work/*/.public/*/ | egrep -v '/(ubuntu|css|js)/') .public/
	block compile index
