# Target OpenEdx release
EDX_RELEASE               ?= master
EDX_ARCHIVE_URL           ?= https://github.com/edx/edx-platform/archive/$(EDX_RELEASE_REF).tar.gz
FLAVOR                    ?= bare
FLAVORED_EDX_RELEASE_PATH  = releases/$(shell echo ${EDX_RELEASE} | sed -E "s|\.|/|")/$(FLAVOR)
EDX_RELEASE_REF           ?= release-2018-08-29-14.14

# Target OpenEdx demo course release
EDX_DEMO_RELEASE_REF      ?= master
EDX_DEMO_ARCHIVE_URL      ?= https://github.com/edx/edx-demo-course/archive/$(EDX_DEMO_RELEASE_REF).tar.gz

# Redis service used
REDIS_SERVICE             ?= redis

# Get local user ids
DOCKER_UID              = $(shell id -u)
DOCKER_GID              = $(shell id -g)

# Docker
COMPOSE          = \
  DOCKER_UID=$(DOCKER_UID) \
  DOCKER_GID=$(DOCKER_GID) \
  FLAVORED_EDX_RELEASE_PATH="$(FLAVORED_EDX_RELEASE_PATH)" \
  docker-compose
COMPOSE_RUN      = $(COMPOSE) run --rm -e HOME="/tmp"
COMPOSE_EXEC     = $(COMPOSE) exec

# Django
MANAGE_CMS       = $(COMPOSE_EXEC) cms python manage.py cms
MANAGE_LMS       = $(COMPOSE_EXEC) lms python manage.py lms

# Terminal colors
COLOR_DEFAULT = \033[0;39m
COLOR_ERROR   = \033[0;31m
COLOR_INFO    = \033[0;36m
COLOR_RESET   = \033[0m
COLOR_SUCCESS = \033[0;32m
COLOR_WARNING = \033[0;33m

# Shell functions
SHELL=bash
define BASH_FUNC_test-service%%
() {
  local service=$${1:-CMS}
  local environment=$${2:-production}
  local url=$${3:-http://localhost:8000}
  local http_version=$${4:-1.1}

  echo -n "Testing $${service} ($${environment})... "
  if curl -vLk --header "Accept: text/html" "$${url}" 2>&1 \
    | grep "< HTTP/$${http_version} 200 OK" > /dev/null ; then
    echo -e "$(COLOR_SUCCESS)OK$(COLOR_RESET)"
  else
    echo -e "$(COLOR_ERROR)NO$(COLOR_RESET)"
	echo -e "\n$(COLOR_ERROR)--- Error traceback ---"
	curl -vLk --header "Accept: text/html" "$${url}"
	echo -e "--- End error traceback ---$(COLOR_RESET)"
  fi
}
endef
export BASH_FUNC_test-service%%

default: help

# Target release expected tree
$(FLAVORED_EDX_RELEASE_PATH)/data/static/production/.keep:
	mkdir -p $(FLAVORED_EDX_RELEASE_PATH)/data/static/production
	touch $(FLAVORED_EDX_RELEASE_PATH)/data/static/production/.keep

$(FLAVORED_EDX_RELEASE_PATH)/data/static/development/.keep:
	mkdir -p $(FLAVORED_EDX_RELEASE_PATH)/data/static/development
	touch $(FLAVORED_EDX_RELEASE_PATH)/data/static/development/.keep

$(FLAVORED_EDX_RELEASE_PATH)/data/media/.keep:
	mkdir -p $(FLAVORED_EDX_RELEASE_PATH)/data/media
	touch $(FLAVORED_EDX_RELEASE_PATH)/data/media/.keep

$(FLAVORED_EDX_RELEASE_PATH)/data/store/.keep:
	mkdir -p $(FLAVORED_EDX_RELEASE_PATH)/data/store
	touch $(FLAVORED_EDX_RELEASE_PATH)/data/store/.keep

$(FLAVORED_EDX_RELEASE_PATH)/data/export/.keep:
	mkdir -p $(FLAVORED_EDX_RELEASE_PATH)/data/export
	touch $(FLAVORED_EDX_RELEASE_PATH)/data/export/.keep

$(FLAVORED_EDX_RELEASE_PATH)/src/edx-demo-course/.keep:
	mkdir -p $(FLAVORED_EDX_RELEASE_PATH)/src/edx-demo-course
	touch $(FLAVORED_EDX_RELEASE_PATH)/src/edx-demo-course/.keep

$(FLAVORED_EDX_RELEASE_PATH)/src/edx-platform/.keep:
	mkdir -p $(FLAVORED_EDX_RELEASE_PATH)/src/edx-platform
	touch $(FLAVORED_EDX_RELEASE_PATH)/src/edx-platform/.keep

# We use this rule to prevent release archive download when it's already
# available. Note that this will also reset edx-platform sources (any changes
# will be discarded).
$(FLAVORED_EDX_RELEASE_PATH)/src/edx-platform/README.rst:
	rm -fr $(FLAVORED_EDX_RELEASE_PATH)/src/edx-platform
	${MAKE} $(FLAVORED_EDX_RELEASE_PATH)/src/edx-platform/.keep
	curl -Lo /tmp/edxapp.tgz $(EDX_ARCHIVE_URL)
	tar xzf /tmp/edxapp.tgz -C $(FLAVORED_EDX_RELEASE_PATH)/src/edx-platform --strip-components=1

$(FLAVORED_EDX_RELEASE_PATH)/src/edx-demo-course/README.md:
	rm -fr $(FLAVORED_EDX_RELEASE_PATH)/src/edx-demo-course
	${MAKE} $(FLAVORED_EDX_RELEASE_PATH)/src/edx-demo-course/.keep
	curl -Lo /tmp/edx-demo.tgz $(EDX_DEMO_ARCHIVE_URL)
	tar xzf /tmp/edx-demo.tgz -C $(FLAVORED_EDX_RELEASE_PATH)/src/edx-demo-course --strip-components=1

bootstrap: \
  stop \
  clean \
  clean-db \
  tree \
  build \
  dev-build \
  migrate \
  run \
  collectstatic \
  demo-course
bootstrap:  ## install development dependencies
.PHONY: bootstrap

# Build production image. Note that the cms service uses the same image built
# for the lms service.
build: \
  info \
  fetch-release
build:  ## build the edxapp production image
	@echo "🐳 Building production image..."
	$(COMPOSE) build lms
.PHONY: build

clean:  ## remove downloaded sources
	rm -Ir \
	  $(FLAVORED_EDX_RELEASE_PATH)/src/* \
	  $(FLAVORED_EDX_RELEASE_PATH)/data/* || exit 0
.PHONY: clean

clean-db: \
  stop
clean-db:  ## Remove mongo, mysql & redis databases
	$(COMPOSE) rm mongodb mysql redis redis-sentinel redis-master redis-slave
.PHONY: clean-db

collectstatic: \
  tree \
  run
collectstatic:  ## copy static assets to static root directory
	$(MANAGE_LMS) collectstatic --noinput --settings=fun.docker_run
	$(MANAGE_CMS) collectstatic --noinput --settings=fun.docker_run
.PHONY: collectstatic

create-symlinks:  ## create symlinks to local configuration (mounted via a volume)
	$(COMPOSE_RUN) --no-deps lms-dev bash -c "\
	  rm -f /edx/app/edxapp/edx-platform/lms/envs/fun && \
	  rm -f /edx/app/edxapp/edx-platform/cms/envs/fun && \
	  ln -sf /config/lms /edx/app/edxapp/edx-platform/lms/envs/fun && \
	  ln -sf /config/cms /edx/app/edxapp/edx-platform/cms/envs/fun && \
	  ln -sf /config/lms/root_urls.py /edx/app/edxapp/edx-platform/lms/"
.PHONY: create-symlinks

demo-course: fetch-demo  ## import demo course from edX repository
	$(COMPOSE_RUN) -v $(PWD)/$(FLAVORED_EDX_RELEASE_PATH)/src/edx-demo-course:/edx/app/edxapp/edx-demo-course cms \
	python manage.py cms import /edx/var/edxapp/data /edx/app/edxapp/edx-demo-course
.PHONY: demo-course

# As we mount edx-platform as a volume in development, we need to re-create
# symlinks that points to our custom configuration
dev: \
  tree \
  create-symlinks
dev:  ## start the cms and lms services (development image and servers)
	# starts lms-dev as well via docker-compose dependency
	$(COMPOSE) up -d cms-dev
	@echo "Wait for services to be up..."
	$(COMPOSE_RUN) dockerize -wait tcp://mysql:3306 -timeout 60s
	$(COMPOSE_RUN) dockerize -wait tcp://cms-dev:8000 -timeout 60s
	$(COMPOSE_RUN) dockerize -wait tcp://lms-dev:8000 -timeout 60s
.PHONY: dev

# In development, we work with local directories (on our host machine) for
# static files and for edx-platform sources, and mount them in the container
# (using Docker volumes). Hence, you will need to run the update_assets target
# everytime you update edx-platform sources and plan to develop in it.
dev-assets: \
  tree \
  create-symlinks \
  dev-install \
  dev-ui-toolkit
dev-assets:  ## run update_assets to copy required statics in local volumes
	$(COMPOSE_RUN) --no-deps lms-dev \
		paver update_assets --settings=fun.docker_build_development --skip-collect
.PHONY: dev-assets

# Build development image. Note that the cms-dev service uses the same image
# built for the lms-dev service.
dev-build:  ## build the edxapp production image
	@echo "🐳 Building development image..."
	$(COMPOSE) build lms-dev
.PHONY: dev-build

# In development, we are mounting edx-platform's sources as a volume, hence,
# since sources are modified during the installation, we need to re-install
# them.
dev-install: \
  $(FLAVORED_EDX_RELEASE_PATH)/src/edx-platform/requirements/edx/local.txt
dev-install:  ## re-install local libs in mounted sources
	$(COMPOSE_RUN) --no-deps lms-dev \
	  pip install -r requirements/edx/local.txt
	$(COMPOSE_RUN) --no-deps lms-dev \
	  npm install
.PHONY: dev-install

# FIXME
#
# Target release: eucalyptus.3
#
# This package should be manually installed from node_modules 🤮
#
# We quit with a 0 exit status if the edx-ui-oolkit dependency has not been
# fetched since we are targeting only a few releases.
dev-ui-toolkit:
	$(COMPOSE_RUN) --no-deps lms-dev \
	  bash -c "cd node_modules/edx-ui-toolkit || exit 0 && npm install"
.PHONY: dev-ui-toolkit

dev-watch: tree  ## start assets watcher (front-end development)
	$(COMPOSE_EXEC) lms-dev \
	  paver watch_assets --settings=fun.docker_build_development
.PHONY: dev-watch

# You can force archive download with the -B option:
#
#   $ make -B fetch-demo
fetch-demo: \
  $(FLAVORED_EDX_RELEASE_PATH)/src/edx-demo-course/README.md
fetch-demo:  ## fetch openedx demo course
	@echo "Demo course release '$(EDX_DEMO_RELEASE_REF)' is available at: $(FLAVORED_EDX_RELEASE_PATH)/src/edx-demo-course/"
.PHONY: fetch-demo

# You can force archive download with the -B option:
#
#   $ make -B fetch-release
fetch-release: \
  $(FLAVORED_EDX_RELEASE_PATH)/src/edx-platform/README.rst
fetch-release:  ## fetch openedx release sources
	@echo "Release '$(EDX_RELEASE_REF)' is available at: $(FLAVORED_EDX_RELEASE_PATH)/src/edx-platform/"
.PHONY: fetch-release

info:  ## get activated release info
	@echo -e "\n.:: OPENEDX-DOCKER ::.\n"
	@echo -e "== Active configuration ==\n"
	@echo -e "* EDX_RELEASE                : $(COLOR_INFO)$(EDX_RELEASE)$(COLOR_RESET)"
	@echo -e "* FLAVOR                     : $(COLOR_INFO)$(FLAVOR)$(COLOR_RESET)"
	@echo -e "* FLAVORED_EDX_RELEASE_PATH  : $(COLOR_INFO)$(FLAVORED_EDX_RELEASE_PATH)$(COLOR_RESET)"
	@echo -e "* EDX_RELEASE_REF            : $(COLOR_INFO)$(EDX_RELEASE_REF)$(COLOR_RESET)"
	@echo -e "* EDX_ARCHIVE_URL            : $(COLOR_INFO)$(EDX_ARCHIVE_URL)$(COLOR_RESET)"
	@echo -e "* EDX_DEMO_RELEASE_REF       : $(COLOR_INFO)$(EDX_DEMO_RELEASE_REF)$(COLOR_RESET)"
	@echo -e "* EDX_DEMO_ARCHIVE_URL       : $(COLOR_INFO)$(EDX_DEMO_ARCHIVE_URL)$(COLOR_RESET)"
	@echo -e "* REDIS_SERVICE              : $(COLOR_INFO)$(REDIS_SERVICE)$(COLOR_RESET)"
	@echo -e ""
.PHONY: info

logs:  ## get development logs
	$(COMPOSE) logs -f
.PHONY: logs

# Nota bene: we do not use the MANAGE_* shortcut because, for some releases
# (e.g.  dogwood), we cannot run the LMS while migrations haven't been
# performed.
migrate:  ## perform database migrations
	@echo "Booting mysql service..."
	$(COMPOSE) up -d mysql
	$(COMPOSE_RUN) dockerize -wait tcp://mysql:3306 -timeout 60s
	$(COMPOSE_RUN) lms python manage.py lms migrate
	$(COMPOSE_RUN) cms python manage.py cms migrate
.PHONY: migrate

run: tree  ## start the cms and lms services (nginx + production image)
	$(COMPOSE) up -d nginx
	@echo "Wait for services to be up..."
	$(COMPOSE_RUN) dockerize -wait tcp://mysql:3306 -timeout 60s
	$(COMPOSE_RUN) dockerize -wait tcp://cms:8000 -timeout 60s
	$(COMPOSE_RUN) dockerize -wait tcp://lms:8000 -timeout 60s
	$(COMPOSE_RUN) dockerize -wait tcp://nginx:8071 -timeout 60s
	$(COMPOSE_RUN) dockerize -wait tcp://nginx:8081 -timeout 60s
.PHONY: run

stop:  ## stop the development servers
	$(COMPOSE) stop
.PHONY: stop

superuser: run  ## create a super user
	$(MANAGE_LMS) createsuperuser
.PHONY: superuser

test: \
  test-cms \
  test-lms \
  test-cms-dev \
  test-lms-dev
test: ## test services (production & development)
.PHONY: test

test-cms: ## test the CMS (production) service
	@test-service CMS production http://localhost:8083 1.1
.PHONY: test-cms

test-cms-dev: ## test the CMS (development) service
	@test-service CMS development http://localhost:8082 1.0
.PHONY: test-cms-dev

test-lms: ## test the LMS (production) service
	@test-service LMS production http://localhost:8073 1.1
.PHONY: test-lms

test-lms-dev: ## test the LMS (development) service
	@test-service LMS development http://localhost:8072 1.0
.PHONY: test-lms-dev

tree: \
  $(FLAVORED_EDX_RELEASE_PATH)/data/static/production/.keep \
  $(FLAVORED_EDX_RELEASE_PATH)/data/static/development/.keep \
  $(FLAVORED_EDX_RELEASE_PATH)/data/media/.keep \
  $(FLAVORED_EDX_RELEASE_PATH)/data/store/.keep \
  $(FLAVORED_EDX_RELEASE_PATH)/data/export/.keep \
  $(FLAVORED_EDX_RELEASE_PATH)/src/edx-demo-course/.keep \
  $(FLAVORED_EDX_RELEASE_PATH)/src/edx-platform/.keep
tree:  ## create data directories mounted as volumes
.PHONY: tree

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
.PHONY: help
