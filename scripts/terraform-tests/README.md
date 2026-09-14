# Terraform functional test harness

Builds `terraform-provider-cloudstack` from a given git SHA or tag and runs a
suite of Terraform test cases against a real CloudStack environment, to
validate that a build actually works end-to-end (not just that it compiles
and unit-tests pass).

## Prerequisites

- `git`, `go`, and `terraform` on `PATH` (only `git` is needed for `--generate-only`)
- A reachable CloudStack environment with API access
- Enough pre-existing environment data to fill in a tfvars file: a zone, a
  template, a network offering, and a VPC offering (see below)

## 1. Prepare a tfvars file

You can either generate one automatically, or copy and fill in the example by hand.

### Option A: generate it (recommended)

Given an environment's API URL and an admin username/password, this logs in,
creates (or reuses) a dedicated `tf-test` account so it never touches your
own API key, generates a key pair for it, and auto-discovers a zone,
template, network offering, and VPC offering:

```sh
./generate-tfvars.sh \
  --api-url http://<mgmt-server>:8080/client/api \
  --username admin --password <password> \
  --out ~/cloudstack-test.tfvars
```

Requires `curl` and `python3`. If the environment has more than one zone,
template, etc. and the auto-picked one isn't the one you want, override it
explicitly:

```sh
./generate-tfvars.sh \
  --api-url http://<mgmt-server>:8080/client/api \
  --username admin --password <password> \
  --zone Sandbox2 \
  --template-name "CentOS 5.5(64-bit) no GUI (KVM)" \
  --network-offering DefaultIsolatedNetworkOffering \
  --vpc-offering "Default VPC offering" \
  --out ~/cloudstack-test.tfvars
```

See `./generate-tfvars.sh --help` for all options (`--domain`, `--account`,
`--kubernetes-version`, etc).

### Option B: copy the example by hand

```sh
cp common/terraform.tfvars.example ~/cloudstack-test.tfvars
```

Edit `~/cloudstack-test.tfvars`:

```hcl
cloudstack_api_url    = "http://localhost:8080/client/api"
cloudstack_api_key    = "..."
cloudstack_secret_key = "..."

zone    = "Sandbox1"                                          # name or ID
zone_id = "00000000-0000-0000-0000-000000000000"               # ID specifically

network_offering = "DefaultIsolatedNetworkOfferingWithSourceNatService"
vpc_offering     = "Default VPC offering"

template_filter     = "executable"
template_name_regex = "^CentOS.*"

kubernetes_version = ""   # only needed if you run the kubernetes-cluster case
```

Either way, keep this file out of version control — it holds real API
credentials. `generate-tfvars.sh` writes it with mode `600`.

## 2. Run the tests

```sh
./run-acs-terraform-tests.sh --ref v0.7.0-rc2 --tfvars ~/cloudstack-test.tfvars
```

`--ref` accepts a tag or a raw commit SHA. It's resolved against this repo,
fetching from `--remote` (default `origin`) if not found locally. The
provider is built in an isolated `git worktree`, so your current working
tree is never touched, and installed as a Terraform local provider under a
version derived from the ref (e.g. `v0.7.0-rc2` -> `0.7.0-rc2`; a raw SHA ->
`0.0.0-<short-sha>`).

Each case under `cases/` is then run through:

1. `terraform init`
2. `terraform validate`
3. `terraform apply -auto-approve`
4. `terraform plan -detailed-exitcode` (confirms no drift right after apply)
5. `terraform destroy -auto-approve` (unless `--keep-resources`)

A summary table is printed at the end, and the script exits non-zero if any
case failed.

### Useful options

| Option | Effect |
| --- | --- |
| `--only '01-*,05-*'` | Run only cases whose directory name matches one of these comma-separated globs |
| `--keep-resources` | Skip `terraform destroy`, so you can inspect what was created after a failure |
| `--keep-workdir` | Keep the worktree and per-case run directories (logs, state) instead of deleting them |
| `--workdir <dir>` | Use a specific directory instead of a fresh temp dir (combine with `--keep-workdir` to reuse it) |
| `--remote <name>` | Git remote to fetch `--ref` from if it isn't already local (default `origin`) |
| `--generate-only` | See below |

Per-case logs (`init.log`, `validate.log`, `apply.log`, `drift-plan.log`,
`destroy.log`) are left under `<workdir>/run/<case>/` — the path is printed
for each case as it runs, and kept around whenever `--keep-workdir`,
`--keep-resources`, or a failure leaves the workdir in place.

### Just look at the generated Terraform files

To render the `.tf`/`.tfvars` files for one or more cases without building
anything or touching a live environment (e.g. to review them, or hand-edit
before applying):

```sh
./run-acs-terraform-tests.sh --generate-only --only '02-*'
```

`--ref` is optional here (the rendered `versions.tf` just gets a placeholder
version), and `--tfvars` defaults to `common/terraform.tfvars.example` if
omitted. The script prints the run directory for each case and exits without
running `terraform` at all.

## Layout

```
common/
  variables.tf              # shared variable declarations, copied into every case
  versions.tf.tmpl          # required_providers + provider block template
                             #   (__PROVIDER_VERSION__ is substituted at run time)
  terraform.tfvars.example  # template for your real tfvars file
cases/
  01-provider-init/
    main.tf                 # one self-contained scenario per directory
  ...
generate-tfvars.sh           # creates a tfvars file from an env's API URL + admin login
run-acs-terraform-tests.sh
```

Each case's `main.tf` is staged together with a fresh copy of
`common/variables.tf`, a rendered `versions.tf`, and your tfvars file into
its own run directory, so cases never share Terraform state.

## Adding a new case

1. Create `cases/<NN>-<name>/main.tf`.
2. Reference the shared variables declared in `common/variables.tf`
   (`var.zone`, `var.zone_id`, `var.network_offering`, `var.vpc_offering`,
   `var.template_filter`, `var.template_name_regex`, `var.kubernetes_version`)
   for anything environment-specific. Add a new variable to
   `common/variables.tf` (and `common/terraform.tfvars.example`) if the case
   needs an environment detail not already covered.
3. Keep the case self-contained — create whatever prerequisite resources it
   needs (e.g. a keypair or network) inside the same `main.tf`, so it can run
   and be destroyed independently of other cases.
4. Verify it renders cleanly with `--generate-only --only '<NN>-*'` before
   running it for real.
5. If the case needs to test an in-place *update* (a config change applied
   on top of an already-applied resource, not just create/destroy), add a
   `main.tf.update` alongside `main.tf` - see "Optional update phase" below.

## Current test cases

All cases below have been run end-to-end against a real CloudStack 4.20 (KVM)
environment.

| Case | Covers |
| --- | --- |
| `01-provider-init` | Provider load + API auth via a `data.cloudstack_template` read (no resources created) |
| `02-service-offering-fixed` | `cloudstack_service_offering_fixed` CRUD |
| `03-service-offering-constrained` | `cloudstack_service_offering_constrained` CRUD |
| `04-service-offering-unconstrained` | `cloudstack_service_offering_unconstrained` CRUD |
| `05-disk-offering-fixed` | `cloudstack_disk_offering` with a fixed `disk_size` |
| `06-disk-offering-customized` | `cloudstack_disk_offering` with `customized = true` |
| `07-network` | Isolated network, auto-assigned CIDR |
| `08-vpc` | VPC against a pre-existing VPC offering |
| `09-instance` | VM lifecycle (own offering/network/keypair) |
| `10-firewall-port-forward` | Firewall + port-forward rules on a VM's source-NAT IP |
| `11-security-group` | Security group + ingress rule (standalone) |
| `12-ssh-keypair` | Auto-generated SSH keypair |
| `13-volume-attach` | Data volume create + attach to a VM |
| `14-static-nat` | Static NAT on a second acquired IP (not the network's source-NAT IP) |
| `15-snapshot-policy` | Recurring snapshot policy on an attached (Ready-state) volume |
| `16-template-datasource` | `data.cloudstack_template` computed fields (format/hypervisor/size) |
| `17-kubernetes-cluster` | Optional - no-op unless `kubernetes_version` is set |
| `18-role` | `cloudstack_role` CRUD |
| `19-role-permission` | `cloudstack_role_permission` ordered-list reconciliation: create, then reorder + insert an entry via `main.tf.update` (see "Optional update phase" below) |
| `20-vpc-offering` | `cloudstack_vpc_offering` CRUD - regression guard for a case-mismatch bug in `internet_protocol`/`routing_mode` that caused a perpetual replace loop |
| `21-network-offering` | `cloudstack_network_offering` CRUD - regression guard for an update-path bug where the offering's ID wasn't set on the update params; `main.tf.update` changes `display_text` |

The `import` scenario from the original test list isn't implemented - it
needs a distinct `terraform import` step the harness doesn't currently
support (init/validate/apply/plan/destroy only).

### Optional update phase (`main.tf.update`)

If a case directory contains a `main.tf.update` alongside `main.tf`, the
harness applies it as a second phase right after the first apply's no-drift
check passes: it overwrites the case's `main.tf` with `main.tf.update`, runs
`apply` again, then checks for a clean follow-up plan (`update` / `update-no-drift`
in the summary line). This is how in-place Update behavior gets exercised -
a single apply/destroy can't test what happens when a config *changes*.
`19-role-permission` and `21-network-offering` use this.

### Provider issues found while building these cases

- **`cloudstack_role_permission`** (`resource_cloudstack_role_permission.go`)
  - real correctness bug. `permission` is an ordered list evaluated top to
  bottom, but the resource's reconciliation logic matches list entries to
  CloudStack's actual role permissions by ID/content without accounting for
  reordering, so **reordering an existing list (optionally combined with
  inserting a new entry) can apply cleanly-looking-but-wrong diffs and then
  fail outright**: reproduced live in `cases/19-role-permission` -
  `terraform plan` shows the 3 existing rules as 3 in-place attribute
  rewrites (rather than recognizing they just moved), and `apply` then
  errors with `Error ordering Role Permissions: ... Invalid parameter
  ruleorder value=<uuid> due to incorrect long value format, or entity does
  not exist` - the id being referenced was already deleted earlier in the
  same reconcile pass. No workaround was added to the fixture for this one
  since the bug prevents the update from completing at all (there's
  nothing to ignore around); the case documents the reproduction as-is.
- **`cloudstack_role`** (`resource_cloudstack_role.go`,
  `resourceCloudStackRoleCreate`) - real correctness bug: `is_public = false`
  is silently ignored. `d.GetOk("is_public")` treats a bool's zero value
  (`false`) as "not set" regardless of whether the user explicitly configured
  it, so `SetIspublic(false)` is never called and CloudStack defaults the
  role to public. Worked around in `cases/18-role/main.tf` with
  `lifecycle { ignore_changes = [is_public] }`. Should use `d.GetOkExists()`
  (or check the resource diff) instead of `GetOk()` for this field. This one
  should be fixed upstream.
- **`cloudstack_snapshot_policy`** (`resource_cloudstack_snapshot_policy.go`,
  `resourceCloudstackSnapshotPolicyRead`) - minor rough edge, not a
  correctness bug: when `zone_ids` isn't configured, CloudStack itself
  defaults the policy to the volume's own zone (expected API behavior), but
  `Read()` writes that server-derived value into `zone_ids` regardless, even
  though the config never set it - causing a spurious "zone_ids forces
  replacement" diff on every subsequent plan. Worked around in
  `cases/15-snapshot-policy/main.tf` with `lifecycle { ignore_changes =
  [zone_ids] }`. The provider could avoid this by only setting `zone_ids` in
  state when the config actually configured it.
