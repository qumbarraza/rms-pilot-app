# rms-pilot-app

Sample ASP.NET Core 8 minimal API for the RMS pilot CI/CD demo. Depends on `RmsPilot.Shared` (from the `rms-pilot-shared` repo) via NuGet, restored from a local pilot feed at `C:\pilot-nuget-feed`.

## The flow this proves

**Pre-merge (short-lived branch validation)**

1. Branch off `master`: `feature/*`, `bugfix/*`, `hotfix/*`.
2. Push: CI builds (compile + tests). No auto-deploy.
3. Developer manually triggers `Branch Deploy (manual)` → picks `dev` or `test` → branch is built and deployed to that env. Anyone can trigger their own branch — last trigger wins the env.
4. Once verified, merge PR to `master`. Branch is deleted on merge.

**Post-merge (artifact promotion)**

5. Merge to `master` triggers `Release` → builds a single versioned, immutable artifact, publishes a GitHub Release, auto-deploys to **Dev** and **Test**.
6. Manual `Promote to Stage` → downloads the same artifact → deploys to **Stage**. Required reviewer gate (GitHub Environment `stage`).
7. Manual `Promote to Prod` → downloads the same artifact → deploys to **Prod (Live)**. Second required reviewer gate (GitHub Environment `prod`).

Same artifact at every gate. No rebuilds.

## Local environments

Each env is a folder; the deploy script drops the published output there. Run any env manually:

| Env   | Folder                              | Port |
|-------|-------------------------------------|------|
| dev   | `C:\pilot-deployments\dev`          | 5001 |
| test  | `C:\pilot-deployments\test`         | 5002 |
| stage | `C:\pilot-deployments\stage`        | 5003 |
| prod  | `C:\pilot-deployments\prod`         | 5004 |

To run an env after a deploy:

```powershell
$env:PILOT_ENV = 'dev'
$env:ASPNETCORE_URLS = 'http://localhost:5001'
dotnet C:\pilot-deployments\dev\RmsPilot.App.dll
```

Then hit <http://localhost:5001/> — you'll see the env name, app version, and shared-lib version in the JSON response. That's how you confirm what got deployed where.

## Branch rules

- All work branches off `master` only
- Allowed prefixes: `feature/*`, `bugfix/*`, `hotfix/*`
- Short-lived; merged or abandoned within the sprint
- Delete-on-merge enforced by repo settings
- No env-named branches: `dev`/`test`/`stage`/`live` are **deployment targets**, not branches
