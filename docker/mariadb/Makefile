SHELL := /bin/bash

COMPOSE := docker compose
MARIA_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: help validate up down reset restart status logs setup

help:
	@printf '%s\n' \
		'make validate  Check the required .env values' \
		'make up        Start MariaDB in the background' \
		'make down      Stop and remove the MariaDB container' \
		'make reset     Remove the container and its data, then start fresh' \
		'make restart   Restart MariaDB while preserving data' \
		'make status    Show the MariaDB container status' \
		'make logs      Follow MariaDB logs' \
		'make setup     Show the connection command and setup information'

validate:
	@cd "$(MARIA_DIR)" && bash scripts/shared/load.sh

up: validate
	@cd "$(MARIA_DIR)" && $(COMPOSE) up -d

down:
	@cd "$(MARIA_DIR)" && $(COMPOSE) down

reset:
	@cd "$(MARIA_DIR)" && $(COMPOSE) down -v
	@$(MAKE) up

restart:
	@cd "$(MARIA_DIR)" && $(COMPOSE) restart

status:
	@cd "$(MARIA_DIR)" && $(COMPOSE) ps

logs:
	@cd "$(MARIA_DIR)" && $(COMPOSE) logs -f mariadb

setup:
	@cd "$(MARIA_DIR)" && bash scripts/shared/print-setup.sh