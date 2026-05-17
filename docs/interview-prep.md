# Interview prep — hardest questions this repo invites

Five questions an experienced interviewer will reach for after reviewing this
repo. Not softballs. Each answer is written the way you should deliver it
verbally: direct claim first, then the reasoning, then the tradeoff you
consciously accepted.

---

## Q1 — "Walk me through your rollback story if a bug ships in a reusable workflow and breaks all ten of your teams simultaneously."

**Why they're asking:**
This is the blast-radius question. Centralised workflows are a force multiplier
in both directions — one fix deploys to everyone, but one bug also breaks
everyone. An interviewer who has run a platform team knows the outage story.
They want to know if you do too.

**How to answer:**

The blast radius is the first thing I think about with centralised workflows,
not an afterthought. The response has three phases: detection, containment,
and recovery.

**Detection** is the part most people skip in the design. If all ten teams
break simultaneously, you need to know within minutes, not when engineers start
filing tickets. In practice that means: the platform team monitors its own
caller (the `examples/` workflows in this repo), and ideally has a canary
caller — a low-stakes internal repo that runs on every merge to `main` before
any tag is cut. If the canary fails, you stop the release.

**Containment** once you've shipped a bad tag depends on how teams are
pinning. This is where the versioning strategy has real consequences:
- Teams pinned to `@v1.0.0` (a specific patch) are frozen. They're broken but
  will not get worse automatically. You have headroom to fix.
- Teams pinned to `@v1` (the floating major tag) are already running the bad
  code. Every new trigger makes it worse.

The immediate action for floating-tag callers is to force-move the `v1`
floating tag back to the last known-good commit:
```bash
git tag -f v1 <last-good-sha>
git push origin v1 --force
```
This is the one legitimate use of force-push in this workflow. The tag is
a mutable pointer by design for this exact scenario.

**Recovery** is a patch release: fix the bug, push `v1.0.1`, move the `v1`
floating tag forward to it, post in whatever communication channel the org
uses (Slack, email, GitHub Discussions). The message needs to be: "what
broke, what the fix is, what teams on `v1.0.0` need to do to unblock
themselves without waiting for Dependabot."

**What I learned from this pattern:** the versioning strategy is not just
ergonomics, it's your incident response tool. If you let every team pin to
`@main`, you have no recovery lever. Semver tags with a documented floating
major give you the ability to push a hot fix to everyone or to stop the
bleeding by reverting the floating tag — without touching each caller repo.

**Tradeoff I consciously accepted:** floating major tags (`v1`) mean a bad
patch auto-deploys to teams that use them. That's a real risk. My mitigation
is the canary caller and the requirement to cut a pre-release tag for any
non-trivial change and let it soak for 24 hours before moving the major tag.
No process survives contact with a deadline, but that's the documented policy.

---

## Q2 — "You've renamed an input in the reusable workflow — `image-name` becomes `image`. How do you manage that change across teams who are at different versions without breaking anyone?"

**Why they're asking:**
Breaking changes in a shared interface are unavoidable over a long enough
timeline. The question tests whether you understand that the technical part
(semver) is the easy part, and the governance part (actually getting teams to
move) is where platform teams fail.

**How to answer:**

The technical mechanism is semver with a deprecation window:

**Phase 1 — add the new input, keep the old one:**
```yaml
inputs:
  image:                     # new canonical name
    required: true
    type: string
  image-name:                # deprecated alias
    required: false          # can't be required — existing callers don't set it
    type: string
    default: ""
```
Inside the workflow, resolve which one to use:
```yaml
- name: Resolve image name
  id: resolve
  run: |
    NAME="${{ inputs.image }}"
    if [[ -z "$NAME" ]]; then
      NAME="${{ inputs.image-name }}"
      echo "::warning::input 'image-name' is deprecated. Rename to 'image'. This alias will be removed in v2."
    fi
    echo "value=$NAME" >> "$GITHUB_OUTPUT"
```
The `::warning::` annotation surfaces in every caller's workflow run in the
GitHub UI — passive pressure without breaking anything.

**Phase 2 — cut a new minor release (`v1.1.0`)**, document the deprecation in
`CHANGELOG.md` with a target removal date (minimum two weeks out, in practice
I use six weeks for an org with ten teams — teams have sprints and code
freezes).

**Phase 3 — audit adoption.** This is the step everyone skips. The GitHub API
lets you query all workflow files across an org:
```bash
gh api search/code \
  --field q="org:YOUR_ORG image-name workflow_call" \
  --jq '.items[].repository.full_name' | sort -u
```
That gives you the list of repos still using `image-name`. You know exactly
who needs to move before you can drop it.

**Phase 4 — cut `v2.0.0`**, remove `image-name` entirely. Teams still on
`@v1` are unaffected — they stay on the last `v1.x` release. Teams who want
the v2 features upgrade and accept the migration cost.

**The governance failure mode:** teams that pin to `@v1.x.x` but never
upgrade even minor versions. Dependabot helps here — it opens PRs for minor
and patch bumps automatically. But some teams have CI noise fatigue and
dismiss Dependabot PRs. The real fix is tracking adoption in a dashboard and
escalating to engineering leads when teams miss the deprecation SLA. The
technical tooling is in service of that conversation, not a substitute for it.

**Tradeoff:** keeping deprecated aliases doubles the surface area of the
inputs contract during the transition period. I accept that because a silent
break is worse than a noisy alias. The `::warning::` annotation makes the
debt visible without blocking anyone.

---

## Q3 — "Why SHA pinning? Dependabot updates the SHAs automatically anyway — you're adding maintenance friction for a threat that Dependabot already handles. Convince me the friction is worth it."

**Why they're asking:**
SHA pinning is in the repo and explained in `security-model.md`. An
interviewer who knows GitHub Actions will push back on it — not because they
disagree, but because they want to hear whether you understand the actual
threat model or just copied the practice from a blog post.

**How to answer:**

Dependabot and SHA pinning solve different problems. Dependabot solves version
drift — it keeps your dependency current. SHA pinning solves supply-chain
compromise — it prevents a tag repoint from executing attacker code before
anyone notices.

Here is the specific gap: Dependabot runs on a schedule, typically weekly. A
compromised action maintainer can repoint a tag at any time. Between the
moment the tag is repointed and the moment Dependabot opens a PR — up to
seven days — every workflow run that references that tag executes the
attacker's code. On a busy org, that is thousands of job runs with full
access to every secret in every caller repo.

SHA pinning collapses that window to zero. A SHA is immutable at the protocol
level — you cannot repoint a commit SHA to different content. The attacker can
repoint the tag all they want; workflows pinned to a SHA are completely
unaffected.

This is not theoretical. In March 2025, `tj-actions/changed-files` had its
version tags repointed to a commit that read runner memory — including secrets
— and printed them to public workflow logs. The repos pinned to specific SHAs
were unaffected. The repos using `@v45` or `@main` ran the malicious code.

**The friction argument:** reading `11bd71901bbe5b1630ceea73d27597364c9af683`
is not ergonomic. I mitigate this with the version comment:
```yaml
uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
```
The SHA is for the runner. The comment is for the human. Dependabot updates
both in a single PR that the platform team reviews in 30 seconds. The
maintenance cost is "review a Dependabot PR once a week." The security gain is
a hard cryptographic guarantee against tag repointing.

**The tradeoff I accepted:** SHA pinning only protects the platform team's
workflows. Product teams calling these workflows are protected from compromises
in the platform's action dependencies, but not from compromises in actions they
add to their own caller workflows. The correct answer to that is org-level
policy enforcement (GitHub Actions allowed actions list), which is a broader
governance topic.

---

## Q4 — "OIDC subject claims — give me three specific scenarios where a platform engineer gets the trust configuration wrong, and explain why each one fails silently with a 401 rather than a meaningful error message."

**Why they're asking:**
The OIDC walkthrough in the README and `security-model.md` shows you understand
the happy path. This question tests whether you've actually debugged a failed
trust configuration, which is where the real understanding lives. "Silently
fails with a 401" is the key phrase — they're probing whether you know why
the errors are unhelpful.

**How to answer:**

The reason every failure returns a generic 401 is that Azure (and GCP's STS)
cannot safely tell you *which* claim mismatched — doing so would help an
attacker enumerate valid subjects. So the error surface is deliberately flat.

**Scenario 1: environment trust configured, workflow_dispatch runs without an environment.**

You set up the federated credential with subject `repo:ORG/REPO:environment:production`
because production deployments should be gated on the Environment. Then
someone manually triggers the workflow via `workflow_dispatch` from the Actions
tab — which does not run inside an Environment unless the job explicitly
declares `environment: production`.

The JWT subject GitHub sends is `repo:ORG/REPO:ref:refs/heads/main`. Azure
compares it to `repo:ORG/REPO:environment:production`. No match. 401.

The engineer stares at the 401, re-checks the secret names, re-checks the
tenant ID, checks the App Registration — everything looks fine, because
everything *is* fine except the subject claim.

Fix: decode the raw OIDC token in the workflow (the debug step in
`security-model.md`) and read the `sub` field directly.

**Scenario 2: PR trust configured for branch, but the PR is from a fork.**

You configure subject `repo:ORG/REPO:pull_request` expecting to allow Terraform
plans on PRs. A contributor opens a PR from a fork. GitHub blocks OIDC token
issuance for fork PRs on the `pull_request` event entirely — the token request
returns a 403, not a 401. The OIDC JWT is never issued, so Azure never even
sees the request.

The engineer configures and reconfigures the federated credential assuming it's
a trust issue. It's not — the token was never issued in the first place.

Fix: understand the fork PR restriction. Plans on fork PRs require `pull_request_target`
with the security split described in section 5 of `security-model.md`, or
you accept that fork contributors do not get plan output on their PRs.

**Scenario 3: tag-triggered deploy trusts `refs/heads/main`, not the tag ref.**

You release by pushing a git tag. The deploy workflow triggers on `push` to
tags matching `v*`. The job tries to authenticate to Azure. The JWT subject
GitHub sends is `repo:ORG/REPO:ref:refs/tags/v1.2.0`. Your federated credential
has subject `repo:ORG/REPO:ref:refs/heads/main`. No match. 401.

The engineer has done every other deploy successfully (from main pushes), so
assumes the credential is correct. It *was* correct for branch-triggered
deploys. Tag-triggered deploys have a different subject.

Fix: add a second federated credential scoped to tag refs, or switch to
environment-based trust which matches regardless of branch or tag:
`repo:ORG/REPO:environment:production`.

**The meta-point:** subject claims are a tuple of (repo, trigger type). Every
trigger type produces a different subject. The debugging tool is always the
same: decode the JWT and compare `sub` character-for-character against the
credential. Azure will not tell you which field mismatched — you have to find
it yourself.

---

## Q5 — "`pull_request_target` exists specifically to give fork PRs access to secrets. Why don't you use it? Walk me through exactly how an attacker exploits it, and show me where in your repo you deliberately avoided it."

**Why they're asking:**
`pull_request_target` is a well-documented footgun and a common source of
secret exfiltration vulnerabilities. An interviewer who cares about supply
chain security wants to know if you understand the exploit, not just that
you've heard "don't use `pull_request_target`."

**How to answer:**

`pull_request_target` runs in the context of the *base* repository with the
base repo's full token, including all secrets. That is its purpose — it exists
so you can safely comment on PRs from forks, post status checks, etc.

The exploit requires only one mistake: checking out the PR's code inside a
`pull_request_target` job that has secret access.

**Exact exploit chain:**
1. Attacker opens a PR from a fork.
2. The workflow uses `pull_request_target` (so it has secrets).
3. The workflow checks out the PR's code:
   ```yaml
   - uses: actions/checkout@...
     with:
       ref: ${{ github.event.pull_request.head.sha }}  # attacker's code
   ```
4. A subsequent step runs a script from the checked-out code — e.g.,
   `make test`, `./scripts/ci.sh`, anything that executes attacker-controlled
   files.
5. The attacker's script reads `$AZURE_CLIENT_ID`, `$AZURE_TENANT_ID`, and
   any other environment-injected secrets, and exfiltrates them to an
   attacker-controlled endpoint.
6. The OIDC credential is now in attacker hands. With Azure OIDC specifically,
   this is limited by the subject claim — the attacker can only use it from
   a workflow that generates the correct subject. But for long-lived secrets
   (if you have any), the exfiltration is immediate and unrestricted.

This is not hypothetical. GitHub Security Lab documented it as
"pwn requests" in 2021. It has been exploited in real repos.

**Where this repo avoids it:**

The consumer example in `examples/app-with-helm/.github/workflows/ci.yml`
splits on event type:
```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build-scan-push:
    uses: .../container-build-scan-push.yml@v1.0.0
    with:
      push: ${{ github.event_name != 'pull_request' }}
    secrets: inherit
```

On `pull_request`: the workflow runs, the image is built and scanned, but
`push: false` means no registry authentication is attempted and no secrets
are used for cloud auth. The scan result is still useful — the PR author gets
vulnerability feedback without the workflow needing OIDC credentials.

On push to `main`: `push: true`, secrets are passed, the image is
authenticated and pushed.

The key architectural decision is that `pull_request` events never need cloud
credentials in this repo's model. Read-only quality checks (helm lint,
kubeconform, ruff, mypy, pytest) need no secrets at all. The registry push
and any cloud write operation is gated on merge to a protected branch.

**The one thing `pull_request_target` is safe for:** posting a comment on a
PR from a fork without checking out the fork's code. The Terraform plan comment
step in `terraform-plan-apply.yml` uses `github-script` to post a comment —
it reads a plan file from the workflow's own file system, never from the PR's
code. That pattern is safe because there is no attacker-controlled code
execution in the comment-posting job.

**Tradeoff:** fork contributors to this repo's example apps do not get a
Terraform plan on their PR. They get a red "plan step skipped" or they get the
scan output on the container build. That is an intentional product decision —
the security boundary is worth the degraded fork-PR experience, and most
platform repos are not accepting external contributions to infrastructure
anyway.
