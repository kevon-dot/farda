# Backend deployment operations

This directory contains a platform-neutral application template. It does not
provision cloud accounts, databases, DNS, TLS, or secrets and it does not deploy
anything. The two images build without credentials. `compose.yaml` refuses to
start until the required runtime values are supplied in `deploy/.env` or by the
deployment platform.

## Release artifacts and provenance

Both Dockerfiles use Node 24, frozen pnpm lockfiles, a non-root runtime user, and
OCI image labels. Build each release from an approved immutable commit and pass
the same values to both images:

```sh
docker build --target runtime \
  --build-arg BUILD_VERSION=1.4.0-staging \
  --build-arg VCS_REF=FULL_GIT_COMMIT_SHA \
  --build-arg BUILD_DATE=2026-10-17T12:00:00Z \
  -t registry.example/farda-api:FULL_GIT_COMMIT_SHA farda-app-backend

docker build --target runtime \
  --build-arg BUILD_VERSION=1.4.0-staging \
  --build-arg VCS_REF=FULL_GIT_COMMIT_SHA \
  --build-arg BUILD_DATE=2026-10-17T12:00:00Z \
  -t registry.example/smart-vial-api:FULL_GIT_COMMIT_SHA smart-vial-backend
```

The values appear in the image labels and in both probe responses under
`build.version`, `build.commit`, and `build.builtAt`. Release tooling should use
the full commit SHA, an immutable image digest, and an RFC 3339 UTC build time.
Do not put tokens, URLs containing credentials, or customer data in build args.

The main API Dockerfile also has a `migration` target. Keep that release image
at the exact same commit as the runtime image. Do not rebuild a mutable tag
between migration and rollout.

## Required runtime configuration

| Service | Required values | Notes |
| --- | --- | --- |
| Main API | `DATABASE_URL`, `BETTER_AUTH_SECRET`, `BETTER_AUTH_URL` | The auth secret must be at least 32 characters and the production auth URL must use HTTPS. Set `HOST=0.0.0.0` in a container. |
| Smart vial API | `MONGODB_URI`, `DATABASE_URL`, `CORS_ORIGINS` | MongoDB must be a replica set or sharded deployment. `DATABASE_URL` must point to the same PostgreSQL identity store used by the main API. |
| Release jobs | `MIGRATION_DATABASE_URL`, `MONGODB_PREPARE_URI` | These short-lived identities may apply Prisma migrations or create MongoDB indexes. Do not give those schema privileges to runtime identities. |

Store these values in the platform's secret manager. Grant the runtime identity
only the database access it needs. Do not bake `.env` files into images or place
real values in `deploy/.env.example`. The template keeps optional AI, refill
provider, and outbound reminder functionality disabled until their separate
activation checks are complete.

Terminate TLS at a trusted ingress and leave the example host port bindings on
loopback for local work. In staging, remove the host `ports` entries when the
platform routes to container ports directly. Do not expose PostgreSQL or MongoDB
to the public network.

## Database release jobs

Back up and rehearse both datastores before a production release. PostgreSQL
schema changes use checked-in Prisma migrations; never use `prisma db push` or
`prisma migrate reset` against staging or production.

Run the main API migration image once for each release:

```sh
docker build --target migration -t registry.example/farda-api-migrate:FULL_GIT_COMMIT_SHA farda-app-backend
docker run --rm --env-file /secure/path/farda-main-migration.env \
  registry.example/farda-api-migrate:FULL_GIT_COMMIT_SHA
```

Then run the vial database preparation command from the vial runtime image:

```sh
docker run --rm --env-file /secure/path/farda-vial-prepare.env \
  registry.example/smart-vial-api:FULL_GIT_COMMIT_SHA \
  node scripts/prepare-database.js
```

`pnpm db:migrate` applies only pending Prisma migrations. `pnpm db:prepare` on
the vial service validates both database connections, requires transactional
MongoDB topology, and creates the declared MongoDB indexes. Both jobs are
idempotent, but only one release controller should run them at a time. A failed
job blocks rollout. The vial preparation job must run only after the PostgreSQL
migration succeeds because it verifies the shared session store. Runtime vial
instances connect without topology-admin or index-creation calls and can use a
MongoDB role limited to application reads and writes. Database rollback means
restoring a verified snapshot to a new database and switching services according
to the rehearsed recovery plan; there is no automatic destructive down-migration.

The two release-job env files above map their privileged database URL to the
command's expected `DATABASE_URL` or `MONGODB_URI` name. Keep them separate from
the runtime env files and inject them from the deployment secret manager.

## Local or staging Compose template

The Compose file builds both runtime images, runs the database jobs, and starts
the APIs only after the jobs succeed. It expects existing PostgreSQL and MongoDB
instances so the same template works with local containers, hosted development
databases, or managed staging databases.

```sh
cp deploy/.env.example deploy/.env
# Replace every placeholder in deploy/.env. Never commit that file.
docker compose --env-file deploy/.env -f deploy/compose.yaml config
docker compose --env-file deploy/.env -f deploy/compose.yaml build
docker compose --env-file deploy/.env -f deploy/compose.yaml up -d
```

Use `docker compose ... logs farda-migrate vial-prepare` to retain the job
outcome, then check both readiness endpoints. `docker compose down` stops the
application containers; it does not remove or alter the external databases.

## Health, readiness, rollout, and rollback

`GET /health` is a process liveness check. It stays healthy during a database
outage so an orchestrator does not create a restart loop. `GET /ready` verifies
the dependencies needed to accept traffic: PostgreSQL for the main API, and
both MongoDB and the shared PostgreSQL session store for the vial API. A failed
check returns HTTP 503 without returning database errors or credentials.
The vial process starts its HTTP listener before attempting datastore recovery,
so liveness remains observable during an initial outage and readiness retries
MongoDB connection. Main API PostgreSQL probes use one coalesced dedicated
client with two-second connection, query, and server statement limits; repeated
health traffic cannot accumulate unresolved work in the application pool.

Configure the platform as follows:

| Setting | Value |
| --- | --- |
| Container/liveness probe | `/health`, port `8000` or `5000` |
| Traffic/readiness probe | `/ready`, same service port |
| Initial delay | At least 15 seconds |
| Probe timeout | At least 4 seconds |
| Shutdown grace | At least 30 seconds |

For a release, record the image digests, commit SHA, migration output, restored
backup evidence, environment, operator, and probe results. Roll out a small
number of instances first, confirm `/ready`, authentication, one owner-scoped
read, and logs/metrics, then continue. Stop and roll back the application image
if readiness or smoke checks fail. Do not call a release successful based only
on `/health`; it deliberately does not test dependencies or authenticated data.

The main API drains HTTP requests and workers for up to 30 seconds on SIGTERM.
The vial API stops accepting requests and closes its PostgreSQL and MongoDB
connections. The reminder worker uses database serialization across processes,
but outbound provider flags should remain disabled until monitoring and provider
runbooks are approved.
