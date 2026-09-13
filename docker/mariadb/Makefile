SHELL := /bin/bash

COMPOSE := docker compose
MARIA_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: help up down reset recreate reset-hard restart status logs connect setup

help:
	@printf '%s\n' \
		'make up        Start MariaDB in the background' \
		'make down      Stop and remove the MariaDB container' \
		'make reset     Recreate MariaDB while preserving volumes' \
		'make recreate  Recreate MariaDB while preserving volumes' \
		'make reset-hard Permanently delete volumes and start fresh' \
		'make restart   Restart MariaDB while preserving data' \
		'make status    Show the MariaDB container status' \
		'make logs      Follow MariaDB logs' \
		'make connect   Show commands for connecting to MariaDB' \
		'make setup     Alias for connect'

up:
	@cd "$(MARIA_DIR)" && $(COMPOSE) up -d

down:
	@cd "$(MARIA_DIR)" && $(COMPOSE) down

reset: recreate

recreate:
	@cd "$(MARIA_DIR)" && $(COMPOSE) down
	@$(MAKE) up

reset-hard:
	@read -r -p 'This will permanently delete all MariaDB data volumes. Continue? [y/N] ' answer; \
	if [[ "$$answer" != [yY] ]]; then \
		echo 'Reset cancelled; volumes and data were preserved.'; \
		exit 0; \
	fi; \
	cd "$(MARIA_DIR)" && $(COMPOSE) down -v && $(MAKE) up

restart:
	@cd "$(MARIA_DIR)" && $(COMPOSE) restart

status:
	@cd "$(MARIA_DIR)" && $(COMPOSE) ps

logs:
	@cd "$(MARIA_DIR)" && $(COMPOSE) logs -f mariadb

connect:
	@source .env && printf '%s\n' \
		'' \
		'Connect from the host:' \
		"mariadb -h 127.0.0.1 -P $${MARIADB_PORT:-3306} -u $${MARIADB_USER:-appuser} -p $${MARIADB_DATABASE:-app}" \
		'' \
		'Connect as root:' \
		"mariadb -h 127.0.0.1 -P $${MARIADB_PORT:-3306} -u root -p" \
		'' \
		'If the mariadb utility is not installed, use one of:' \
		'  Debian/Ubuntu: sudo apt install mariadb-client' \
		'  Fedora/RHEL:   sudo dnf install mariadb' \
		'  Alpine:        sudo apk add mariadb-client' \
		'  Homebrew:      brew install mariadb-connector-c'

setup: connect