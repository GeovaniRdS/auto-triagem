# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project purpose

This repo builds a **labeled dataset of CI/CD pipeline failure logs** by deliberately sabotaging a real
CI/CD pipeline (GitHub Actions self-hosted runner → build → test → Docker build → deploy to a local k3s
cluster) and capturing the resulting failure logs. The end goal is to train a classifier (`classifiers/`,
currently empty) that can automatically triage which stage/class a CI/CD failure belongs to. `docs/` is
also currently empty (reserved for future documentation/diagrams).

The service under test, `currencyservice` (`ci-service/src/currencyservice`), is the gRPC currency
conversion microservice from Google's `microservices-demo`, used here only as a realistic pipeline
target — its own application logic is not the focus of this repo.

## Repository layout

- `ci-service/src/currencyservice/` — the Node.js gRPC microservice deployed by the pipeline
  (`server.js`, `client.js`, `test.js`, `Dockerfile`, `package.json`).
- `.github/workflows/ci-cd.yml` — the single pipeline: `npm install` → `npm test` → `docker build` →
  import image into k3s's containerd → `kubectl apply` the manifest → `kubectl rollout status`. Runs on
  a **self-hosted** runner, triggered on pushes touching `ci-service/src/currencyservice/**`,
  `manifests/**`, or `.github/workflows/**`.
- `manifests/currencyservice.yaml` — Kubernetes Deployment/Service/ServiceAccount applied to the local
  k3s cluster.
- `fault-injection/` — scripts that sabotage the pipeline to produce labeled failure samples (see below).
- `data/dataset.csv` — dataset index: `sample_id,classe,run_id,log_path,timestamp`.
- `data/raw_logs/<classe>/sample_NNN.log` — captured raw logs, one folder per failure class:
  `build`, `teste`, `push_imagem`, `manifesto_invalido`, `imagepullbackoff`, plus `admissao` and
  `crashloopbackoff` folders reserved for classes not yet scripted.
- `classifiers/` — empty; intended home for the future classifier code.

## Fault-injection workflow

Each `fault-injection/inject_<classe>_failure.sh <sample_num> <variant>` script follows the same shape:

1. Verify the self-hosted runner is alive (`pgrep -f "Runner.Listener"`); abort with an error telling
   the user to start it (`cd ~/actions-runner && ./run.sh`) if not.
2. Back up the file(s) it's about to sabotage to `/tmp/*.backup`.
3. Apply one of 5 `sed`-based sabotage variants (selected by `$VARIANT`) to a config/source file
   (`package.json`, `Dockerfile`, `test.js`, the workflow file, or the manifest).
4. `git commit` + `git push` the sabotage — this is what triggers the real CI run.
5. Locate the triggered run (`gh run list`/`gh run view`, matched by `headSha` for scripts that can race
   with other pushes) and poll until `status == completed`.
6. Capture `gh run view --log-failed` into `data/raw_logs/<classe>/sample_<N>.log` (the
   `imagepullbackoff` script additionally appends `kubectl describe pod` output, since that failure
   surfaces at the cluster level, not in the GitHub Actions log).
7. Append a row to `data/dataset.csv`.
8. **Restore the sabotaged file(s) from the `/tmp` backup (not via `git revert`)**, then `git add -A`,
   commit as `revert: fault-injection <classe> failure amostra <N>`, and push again.

`fault-injection/run_batch_<classe>.sh` loops the corresponding inject script over a range of sample
numbers, cycling through variants 1–5 via modulo arithmetic, and stops the whole batch if any single
invocation fails.

Things to preserve when touching this machinery:

- The paired `fault-injection: ... variante N (amostra NNN)` / `revert: fault-injection ... amostra NNN`
  commits are intentional and expected in git history — don't "clean up" or squash them.
- `REPO=~/projetos/auto-triagem` is hardcoded in every script; scripts assume they're run from/for that
  path with `gh` authenticated and a working local `kubectl`/k3s context.
- Sample numbers are zero-padded 3-digit strings from `seq -w`, but early manual samples in
  `data/dataset.csv` (before the batch scripts existed) use inconsistent widths (`03`, `002`, etc.) —
  this is historical, not a bug to fix retroactively.

## Running the pipeline / tests locally

- Microservice tests: `cd ci-service/src/currencyservice && npm install && npm test`
  (runs `test.js`, which asserts `data/currency_conversion.json` is non-empty and contains `USD`).
- The full pipeline only runs via the self-hosted GitHub Actions runner against the local k3s cluster —
  there is no way to exercise `ci-cd.yml` end-to-end without that runner and cluster present.
