# Synthoria

Déploiement complet de Synthoria avec un seul `docker-compose.yml` et un seul `.env` :

- **Synthoria LLM** (FastAPI) : API, worker de podcasts, synthèse vocale Piper ;
- **Synthoria Studio** (Next.js) : interface web.

Les images sont construites et publiées sur GHCR par la CI de chaque dépôt (tests verts obligatoires). Ce dépôt ne contient aucun code applicatif : il les assemble et les tient à jour avec Watchtower.

## Services

| Service | Image | Rôle | Exposé sur l'hôte |
| --- | --- | --- | --- |
| `studio` | `ghcr.io/mahandry-it/synthoria-studio` | Interface web, relaie `/api/*` vers `api` | `3000` |
| `api` | `ghcr.io/mahandry-it/synthoria-llm` | API FastAPI | `8000` |
| `worker` | `ghcr.io/mahandry-it/synthoria-llm` | Génération des podcasts | non |
| `piper` | `ghcr.io/mahandry-it/synthoria-piper` | Synthèse vocale (TTS) | non |
| `piper-init` | `ghcr.io/mahandry-it/synthoria-piper` | Télécharge la voix (une fois) | non |
| `ollama` | `ollama/ollama` (version épinglée) | LLM local et embeddings | non |
| `ollama-init` | `ollama/ollama` (version épinglée) | Tire les modèles (une fois) | non |
| `postgres` | `postgres` (version épinglée) | Base de données | non |
| `chroma` | `chroma` (version épinglée) | Base vectorielle | non |
| `watchtower` | `nickfedor/watchtower` (version épinglée) | Mise à jour automatique | non |

Le studio appelle l'API par le nom de service `api:8000`, figé dans son image au build : ne pas renommer ce service.

## Prérequis

- Docker Engine 24+ avec le plugin Compose v2 (ou Docker Desktop) ;
- environ 15 Go de disque (images et modèles Ollama) ;
- une clé Gemini, et en option une clé YouTube Data API v3 et des identifiants Openverse.

## Démarrage

```bash
cp .env.example .env    # Windows : Copy-Item .env.example .env
# Renseigner la section « Secrets » et POSTGRES_PASSWORD (obligatoire), par ex. openssl rand -hex 24
make up                 # Windows : ./synthoria.ps1 up
```

Au premier démarrage, `ollama-init` télécharge les modèles (plusieurs Go) avant que l'api ne démarre. Suivre l'avancement avec `make logs S=ollama-init`.

Une fois les services `healthy` (`make ps`) :

- Studio : <http://localhost:3000>
- API : <http://localhost:8000/health> (documentation : `/docs`)

## Commandes

`make` n'existe pas toujours sous Windows : `synthoria.ps1` offre les mêmes commandes.

| make | PowerShell | Effet |
| --- | --- | --- |
| `make up` | `./synthoria.ps1 up` | Démarre la stack en arrière-plan |
| `make down` | `./synthoria.ps1 down` | Arrête la stack, **volumes conservés** |
| `make logs S=api` | `./synthoria.ps1 logs api` | Suit les logs (tous les services sans argument) |
| `make ps` | `./synthoria.ps1 ps` | État des services |
| `make pull` | `./synthoria.ps1 pull` | Télécharge les images du tag courant |
| `make update` | `./synthoria.ps1 update` | `pull` puis recrée les conteneurs modifiés |
| `make rollback TAG=sha-1a2b3c4` | `./synthoria.ps1 rollback sha-1a2b3c4` | Fige le tag dans `.env` puis `update` |

## Mise à jour automatique

```
push sur master (LLM) / main (Studio)
  → CI : tests → build → push GHCR (tags latest + sha-<7>)
  → Watchtower (toutes les WATCHTOWER_POLL_INTERVAL secondes) détecte le nouveau digest
  → recrée uniquement studio, api, worker et piper ; postgres, ollama et chroma ne bougent pas
```

- Watchtower ne surveille que les conteneurs portant `com.centurylinklabs.watchtower.enable=true` **et** le scope `synthoria` ; il ne touche à aucun autre conteneur de l'hôte.
- Le studio est redémarré après une mise à jour de l'api (label `depends-on`).
- `WATCHTOWER_TIMEOUT=60s` laisse au worker le temps de terminer l'étape de podcast en cours.
- `WATCHTOWER_MONITOR_ONLY=true` : notifier sans appliquer ; `WATCHTOWER_NOTIFICATION_URL` : URL [shoutrrr](https://containrrr.dev/shoutrrr/) (Discord, Telegram…).
- Les images doivent être **publiques** sur GHCR. Si elles sont privées : `docker login ghcr.io` avec un PAT `read:packages`, puis monter `~/.docker/config.json` dans le conteneur `watchtower` (`/config.json`).
- Les données vivent dans des volumes nommés (`synthoria_postgres-data`, `synthoria_ollama-data`, …) : une mise à jour ou un `make down` ne les supprime pas. Seul `docker compose down -v` les efface.

## Revenir en arrière

Chaque image est aussi publiée sous un tag immuable `sha-<7 premiers caractères du commit>` (visible dans la page *Packages* du dépôt GitHub concerné).

```bash
make rollback TAG=sha-1a2b3c4     # Windows : ./synthoria.ps1 rollback sha-1a2b3c4
```

Le tag est écrit dans `.env` (`SYNTHORIA_IMAGE_TAG`), donc il survit aux redémarrages ; un tag `sha-*` ne change jamais, Watchtower ne remplacera donc plus ces conteneurs. Pour revenir au suivi automatique : `make rollback TAG=latest`.

Le tag s'applique aux trois images Synthoria : les dépôts LLM et Studio étant publiés séparément, un même `sha-*` n'existe en général que pour l'un des deux. Pour figer un seul composant, remplacer `${SYNTHORIA_IMAGE_TAG:-latest}` par le tag voulu dans la ligne `image:` du service concerné.

## Sécurité

- `.env` contient les secrets : il est ignoré par Git, ne jamais le committer.
- Seuls `studio` et `api` sont publiés sur l'hôte. Derrière un reverse proxy, ne publier que le studio (retirer le port de l'api) et restreindre `CORS_ALLOWED_ORIGINS`.
- Watchtower a accès au socket Docker (équivalent root sur l'hôte) : son image est épinglée et il est limité par label et par scope.
- Monter de version `ollama`, `postgres`, `chroma` ou `watchtower` se fait en modifiant le tag dans `docker-compose.yml` (jamais `latest`). Pour Postgres, un changement de version majeure exige une migration des données (`pg_dump` / `pg_restore`).
