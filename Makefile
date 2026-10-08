# Raccourcis Docker Compose (équivalent Windows : ./synthoria.ps1 <commande>).
COMPOSE ?= docker compose
ENV_FILE := .env

.PHONY: help up down logs ps pull update rollback

help: ## Liste les commandes
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

$(ENV_FILE):
	@echo "Fichier .env absent : cp .env.example .env puis renseigner les secrets." >&2; exit 1

up: $(ENV_FILE) ## Démarre la stack en arrière-plan
	$(COMPOSE) up -d

down: ## Arrête la stack (les volumes sont conservés)
	$(COMPOSE) down

logs: ## Suit les logs (S=api pour un seul service)
	$(COMPOSE) logs -f --tail=200 $(S)

ps: ## État des services
	$(COMPOSE) ps

pull: $(ENV_FILE) ## Télécharge les images du tag courant
	$(COMPOSE) pull

update: pull ## Télécharge puis recrée les conteneurs modifiés
	$(COMPOSE) up -d

rollback: $(ENV_FILE) ## Fige SYNTHORIA_IMAGE_TAG=TAG dans .env puis met à jour (TAG=sha-xxxxxxx)
	@echo "$(TAG)" | grep -Eq '^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$$' || { echo "Usage : make rollback TAG=sha-xxxxxxx (ou TAG=latest)" >&2; exit 1; }
	@if grep -q '^SYNTHORIA_IMAGE_TAG=' $(ENV_FILE); then \
		sed -i.bak 's/^SYNTHORIA_IMAGE_TAG=.*/SYNTHORIA_IMAGE_TAG=$(TAG)/' $(ENV_FILE) && rm -f $(ENV_FILE).bak; \
	else echo 'SYNTHORIA_IMAGE_TAG=$(TAG)' >> $(ENV_FILE); fi
	@echo "SYNTHORIA_IMAGE_TAG=$(TAG)"
	$(MAKE) update
