# SCEPMan

SCEPman is a cloud-based certification authority. It is installed within minutes and requires virtually no operations efforts.

It easily enables your Intune and JAMF managed clients for certificate based WiFi authentication based on the SCEP protocol, but it can also issue certificates for Domain Controllers or TLS Servers.

Please see https://docs.scepman.com/ for a full documentation.

## Purpose of this Repository

This repository serves the Bicep and ARM templates for deploying SCEPman to an Azure tenant. This repository previously also held the binary SCEPman artifacts and had the address https://github.com/scepman/install. These binary artifacts are now hosted in a new repository under the old address.

## Upstream history rewrite and how to resync your fork

This repository underwent a **one-time history rewrite** at 2025-12-16 to get rid of the voluminous history of SCEPman artifacts now hosted at https://github.com/scepman/install.

### What changed

- **All commit hashes before the rewrite changed**
- Some commits were **dropped**
- **No commits were reordered**
- **Commit author, commit message, and commit timestamp were preserved exactly**
- New commits were added *after* the rewrite

Because of this, existing forks cannot merge or pull from upstream in the usual way.
However, forks **can be safely resynchronized** by rebasing onto the rewritten history, assuming they forked only to modify Bicep code and ARM templates and not the binary artifacts.

---

### What fork maintainers need to do

You need to:
1. Find the **last commit your fork shared with the old upstream**
2. Find the **latest upstream commit *before the rewrite* with the same timestamp**
3. Rebase your fork onto the rewritten upstream

This works even if your fork was created from a commit that no longer exists upstream (because it modified only artifacts, not Bicep/ARM code).

---

#### Step-by-step instructions

Use the code below for either bash or PowerShell.

##### bash
```bash
# 1. Add (or update) the upstream remote

git remote add upstream https://github.com/scepman/deploy.git 2>/dev/null || \
git remote set-url upstream https://github.com/scepman/deploy.git
git fetch upstream

# 2. Find the last commit in your fork that has a matching commit in upstream
#    (same timestamp, author, and message)

# Get all origin commits with their metadata
git log origin/master --format="%H|%ct|%an|%s" > /tmp/origin_commits.txt

# Get all upstream commits with their metadata
git log upstream/master --format="%H|%ct|%an|%s" > /tmp/upstream_commits.txt

# Find the first (most recent) origin commit that has a match in upstream
while IFS='|' read -r hash timestamp author message; do
    MATCH=$(grep -F "|${timestamp}|${author}|${message}" /tmp/upstream_commits.txt | head -1)
    if [ -n "$MATCH" ]; then
        ORIGIN_COMMIT="$hash"
        UPSTREAM_COMMIT=$(echo "$MATCH" | cut -d'|' -f1)
        echo "Found matching commits:"
        echo "  Origin:   $ORIGIN_COMMIT"
        echo "  Upstream: $UPSTREAM_COMMIT"
        break
    fi
done < /tmp/origin_commits.txt

# Clean up temp files
rm /tmp/origin_commits.txt /tmp/upstream_commits.txt

# 3. Rebase your fork onto the rewritten upstream at the commit this was originally forked from

git checkout master
git rebase --onto $UPSTREAM_COMMIT $ORIGIN_COMMIT master

```

##### PowerShell

```pwsh
# 1. Add (or update) the upstream remote

git remote add upstream https://github.com/scepman/deploy.git 2>$null
git remote set-url upstream https://github.com/scepman/deploy.git
git fetch upstream

# 2. Find the last commit in your fork that has a matching commit in upstream
#    (same timestamp, author, and message)

# Get all origin commits with their metadata
$originCommits = git log origin/master --format="%H|%ct|%an|%s" | ForEach-Object {
    $parts = $_ -split '\|', 4
    [PSCustomObject]@{
        Hash      = $parts[0]
        Timestamp = $parts[1]
        Author    = $parts[2]
        Message   = $parts[3]
    }
}

# Build a hashtable of upstream commits keyed by timestamp|author|message
$upstreamLookup = @{}
git log upstream/master --format="%H|%ct|%an|%s" | ForEach-Object {
    $parts = $_ -split '\|', 4
    $key = "$($parts[1])|$($parts[2])|$($parts[3])"
    if (-not $upstreamLookup.ContainsKey($key)) {
        $upstreamLookup[$key] = $parts[0]
    }
}

# Find the first (most recent) origin commit that has a match in upstream
$ORIGIN_COMMIT = $null
$UPSTREAM_COMMIT = $null

foreach ($originCommit in $originCommits) {
    $key = "$($originCommit.Timestamp)|$($originCommit.Author)|$($originCommit.Message)"
    if ($upstreamLookup.ContainsKey($key)) {
        $ORIGIN_COMMIT = $originCommit.Hash
        $UPSTREAM_COMMIT = $upstreamLookup[$key]
        Write-Host "Found matching commits:"
        Write-Host "  Origin:   $ORIGIN_COMMIT"
        Write-Host "  Upstream: $UPSTREAM_COMMIT"
        break
    }
}

if (-not $ORIGIN_COMMIT) {
    Write-Error "No matching commit found between origin and upstream"
    exit 1
}

# 3. Rebase your fork onto the rewritten upstream

git checkout master
git rebase --onto $UPSTREAM_COMMIT $ORIGIN_COMMIT master
```

##### Push to Origin

After this, you might want to check your logs to ensure the history looks good now. Then, force push to origin to get the resynchronized state back to GitHub/server repository.

```bash
git push --force-with-lease origin master
```

#### Result

Your fork will be fully aligned with the rewritten upstream history and its merge-base is the commit in upstream matching the original merge-base. You still have to do a merge or rebase to incorporate the new commits in upstream into your fork, if there are any. You only had to do this re-alignment once, and you can get future upstream changes from scepman/deploy with regular merges or rebases.

#### Resync Problems

Please open an issue or contact [SCEPman support](https://support.scepman.com/support/tickets/new?ticket_form=technical_support_request_(scepman)) if you run into problems re-synchronizing with this repository.