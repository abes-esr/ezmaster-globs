Dépôt git archivé depuis le 20/08/2025 car les dépôts github d'abes-esr sont [archivés sur software heritage](https://archive.softwareheritage.org/browse/search/?q=abes-esr).

# ezmaster-globs

[![Build Status](https://travis-ci.org/Inist-CNRS/ezmaster-globs.svg?branch=master)](https://travis-ci.org/Inist-CNRS/ezmaster-globs) [![Docker Pulls](https://img.shields.io/docker/pulls/inistcnrs/ezmaster-globs.svg)](https://registry.hub.docker.com/u/inistcnrs/ezmaster-globs/)

GLoBS : *Github LOcal Backup Server*

L'objectif de cette application est de sauvegarder localement des clones de dépôts GitHub afin de proposer un moyen de sauvegarde et de pouvoir temporairement s'y synchroniser dans le cas où github est down.

L'application permet de :

- régulièrement (variable `DUMP_EACH_NBMINUTES`) cloner et se synchroniser avec les dépôts des organisations github passées en argument (variable `GITHUB_ORGANIZATIONS`). A noter que seules les oganisations github sont gérées, les dépôt rattachés à des comptes github ne le sont pas.
- mettre à disposition les dépôts clonés à travers un serveur web (protocole http) et ainsi permettre de réaliser des `git clone` en lecture seule de ces dépôts
- (optionnellement) réaliser un miroir des dépôts sur une instance gitlab
- (optionnellement) être déployée sur [ezmaster](https://github.com/Inist-CNRS/ezmaster)

## Variables de configuration

- `DUMP_EACH_NBMINUTES` doit contenir le temps à attendre (en minutes) entre chaque sauvegarde/synchronisation. Par défaut 5 minutes.
- `DUMP_TO` doit contenir la liste des emplacement où sauvegarder : "local" et/ou "gitlab". Par défault uniquement "local"

---

- `GITHUB_ORGANIZATIONS` doit contenir la liste des organisations github que vous souhaitez sauvegarder.
- `GITHUB_PERSONAL_ACCESS_TOKEN` doit contenir le token OAUTH issu d'un compte github pour pouvoir naviguer via l'API de github dans la liste des dépôts et pouvoir dépasser la [limite de requêtes en mode anonyme](https://developer.github.com/v3/#rate-limiting). Pour le générer, rendez-vous ici : https://github.com/settings/tokens (attention ce token ne doit pas être partagé)

---

- `GITLAB_HTTP_BASEURL` doit pointer vers la racine http(s) de votre instance gitlab cible vers laquelle vous souhaitez réaliser des miroirs (sans le / de fin). Cette URL sera utilisée pour l'accès à l'API (v4) de Gitlab. Exemple : "https://git.abes.fr"
- `GITLAB_SSH_BASEURL` doit pointer vers la racine de l'accès SSH du dépôt git sous gitlab (utilisé au moment de faire un git push vers gitlab via ssh). Exemple: "git@git.abes.fr"
- `GITLAB_PERSONAL_ACCESS_TOKEN` doit contenir le token permettant d'accéder à l'API de votre instance gitlab. Pour le générer, rendez vous ici https://git.abes.fr/profile/personal_access_tokens (adaptez votre baseurl & attention ce token ne doit pas être partagé)
- `GITLAB_GROUP_PREFIX` contient un préfixe optionnel qui sera utilisé au moment de la création des groupes gitlab en miroir des organizations github. Ex: "inist-cnrs" côté github deviendrait "github-backup-inist-cnrs" côté gitlab dans le cas où GITLAB_GROUP_PREFIX vaut "github-backup-"  




## Production sans ezmaster

Utilisez alors docker-compose pour déployer `ezmaster-globs`. Pour cela vous devez juste télécharger le [docker-compose.yml](https://raw.githubusercontent.com/Inist-CNRS/ezmaster-globs/master/docker-compose.yml) prêt pour la production puis l'exécuter en lui passant les paramètres de configuration sous la forme de variables d'environnement de cette manière :

```bash
wget https://raw.githubusercontent.com/Inist-CNRS/ezmaster-globs/master/docker-compose.yml

GITHUB_ORGANIZATIONS="abes-esr inist-cnrs" \
GITHUB_PERSONAL_ACCESS_TOKEN="change me" \
GITLAB_HTTP_BASEURL="https://git.abes.fr" \
GITLAB_SSH_BASEURL="git@git.abes.fr" \
GITLAB_PERSONAL_ACCESS_TOKEN="change me" \
GITLAB_GROUP_PREFIX="github-backup-" \
DUMP_EACH_NBMINUTES=5 \
DUMP_TO="local gitlab" \
docker-compose up
```

- Un conteneur docker nommé `ezmaster-globs` sera alors créé.
- Ajoutez éventuellement l'option `-d` pour le lancer en tâche de fond.
- Veillez à gérer les logs qui seront envoyées sur stdout et stderr du conteneur docker.

## Production avec ezmaster

Utilisez [ezmaster](https://github.com/Inist-CNRS/ezmaster) et déployez l'application `inistcnrs/ezmaster-globs:2.2.3`

Créez ensuite une instance de cette application et paramétrez-la en modifiant ces variables dans la config JSON :

```json
{
  "DUMP_EACH_NBMINUTES": 1,
  "DUMP_TO": [ "local", "gitlab "],
  "GITHUB_ORGANIZATIONS": [ "inist-cnrs", "istex", "abes-esr" ],
  "GITHUB_PERSONAL_ACCESS_TOKEN": "change me",
  "GITLAB_HTTP_BASEURL": "https://git.abes.fr",
  "GITLAB_SSH_BASEURL": "git@git.abes.fr",
  "GITLAB_PERSONAL_ACCESS_TOKEN": "change me",
  "GITLAB_GROUP_PREFIX": "github-backup-"
}
```

## Développements

```bash
npm run build # pour construire l'image docker
npm run debug # pour lancer le serveur web et le clonage
DUMP_EACH_NBMINUTES=1 GITHUB_ORGANIZATIONS="inist-cnrs" npm run debug # pour personnaliser depuis des variables d'env
```

Se connecter ensuite sur http://127.0.0.1:8080/ pour visualiser les dépôts sauvegardées localement.

Vous pouvez ensuite tester des clones git depuis le serveur web fourni par ezmaster-globs. Voici un exemple de clone depuis une instance d'ezmaster-globs en local qui écoute sur le port 8080 :

```
git clone http://127.0.0.1:8080/inist-cnrs/node-xml-writer.git
```

(A noter que `inist-cnrs/node-xml-writer.git` est un dépôt que l'on trouve sur l'organisation github inist-cnrs)

