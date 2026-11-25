---
name: zopen-rpm
description: Use when the user wants to turn a z/OS pax file into an RPM with pax2rpm (zopen-pax2rpm), asks how to package an OEF tool or a product such as the Atlas Discovery Agent as an RPM, or hits problems with a pax-to-RPM build such as garbled text files, ASCII/EBCDIC tagging, untagged-file warnings, a "/bin/sh is needed by" install error, "no signature" errors, wrong file modes, or pre/post-install scripts and license prompts.
---

# Packaging a z/OS pax as an RPM (pax2rpm)

This skill records what was learned packaging the OEF `rsync` pax and the Atlas Discovery Agent (DA) pax as RPMs on z/OS. It is a rule book, not a tutorial on RPM in general. It was last updated on Nov 24, 2026.

Supporting files in `scripts/`:

- `scripts/oef-license-pre.sh`: the license prompt used as `%pre` (see Step 7). The wording is not product-specific, but it names OEF, so check it is right for your product.
- `scripts/zps-discovery-agent-post.sh`: the DA post-install script used as `%post` (see Step 7). **It only applies to the Discovery Agent.** It is an example. Other products must write their own post-install script, or leave `--post-script` out.

**What is and is not inside pax2rpm.** pax2rpm itself contains no license text and nothing specific to the DA. The two scripts above are separate files that you hand to pax2rpm with the `--pre-script` and `--post-script` options. Those two options are local additions and are not in the standard pax2rpm yet.

## How to use this skill

1. Answer the user in plain terms. Many users know z/OS and pax but not RPM.
2. You cannot run commands on the user's z/OS system. Give exact commands for the user to run and ask them to paste the output.
3. Give one command per code block, with real values. A `<` typed in a shell command is read as input redirection, so never give a command with a `<placeholder>`. Set a shell variable for long paths instead, for example `R=/path/to/the.rpm`.
4. Separate what was proven from what was not. The "Status" notes below say which is which. Do not claim a step works if it is marked untested.

## Background in four lines

- A **pax** is the archive format OEF ships today (`<tool>-<version>.<timestamp>.zos.pax.Z`).
- An **RPM** is a package the system records: version, files, and the ability to upgrade, verify (`rpm -V`) and remove (`rpm -e`).
- A **spec file** is the recipe `rpmbuild` follows. `pax2rpm` writes it for you from the pax.
- On z/OS the tool is `zopen-pax2rpm`. It writes the spec, then calls `zopen-rpmbuild`, which must sit in the same folder.

## Step 1: Inspect the pax before building

1. Run `export PATH=/zopen/usr/local/altbin:$PATH` at the start of every z/OS session. This puts GNU `find` first. Do not use `export PATH=/bin:$PATH`.
2. List the pax: `pax -f <file>.pax` (for a `.pax.Z`, use `pax -zf <file>`). Write down the file count.
3. Check whether the files are tagged. Extract to a scratch directory and run `ls -T` on the text files.
4. Check disk space with `df -k <dir>`. A build needs roughly 200 MB free for a 57 MB pax. `No space left on device` happened twice on a small test filesystem. Point `--buildroot` at a filesystem with room.

## Step 2: Make sure the files in the pax are tagged

z/OS files carry a code-page tag. rpm needs every file in the pax to be tagged correctly. Untagged ASCII text files are the main cause of garbled RPMs.

- ASCII text files (scripts, `.yaml`, `.md`, `.txt`): tag `ISO8859-1` before packing, with `chtag -tc ISO8859-1 <file>`.
- Binaries and wheels: `chtag -b <file>` is the preferred tag. The build and the install print a warning for each untagged file, for example `file ... is untagged; its encoding is unspecified`. **Status, proven:** the DA build and install with an untagged binary and untagged wheels still finished successfully, with those warnings, and the binary's hash matched the pax. A `chtag -b` binary was **not tested** through pax and pax2rpm.
- Build the pax with `pax -w -x pax`. **Status, proven:** this format keeps tags through a round trip.

Why this matters (proven on z/OS):

- `/bin/sed` reads an untagged ASCII file as if it were EBCDIC and writes back a trailing `0x15` (the EBCDIC newline). The file then reads as one line.
- A tagged ISO8859-1 file read by `/bin/sed` is converted to EBCDIC and written back tagged IBM-1047, with a final newline added. rpm stores a Latin-1 conversion, so the text survives. A file with no final newline gains one byte, so its digest changes.
- `sha256sum` reads raw bytes even on tagged files, so digests are a reliable check.

## Step 3: Check that pax2rpm has the guard

pax2rpm runs `sed` over every file to replace the `ZOPEN_INSTALL_PREFIX` placeholder. The guard skips `sed` for files that do not contain that placeholder. The guard is a local change and is not in the standard pax2rpm yet.

1. Look for the guard in pax2rpm: `grep -n "sed -e" zopen-pax2rpm`. The line should read `if /bin/sed -e "" "${f}" 2> /dev/null 1>&2 && /bin/grep -q "${orig}" "${f}" 2> /dev/null; then`.
2. If the line has no `/bin/grep -q "${orig}"` part, pax2rpm has no guard. Every file goes through `sed`. Binaries and wheels are at risk, and a text file without a final newline gets one added.
3. Non-zopen products such as the DA have no `ZOPEN_INSTALL_PREFIX` in their files, so the guard skips every file. **Status, proven:** with the guard, all five DA text files matched the pax byte for byte after install. With the tagged pax and no guard, four matched and `requirements-zos.txt` (no final newline) did not.
4. Workaround if the guard is missing: end every text file with a newline and tag it `ISO8859-1`. It is a workaround only, and it is **not tested**.

The guard did **not** fix `rsync`. Its `README.txt` is real EBCDIC tagged IBM-1047. rpm stores a Latin-1 copy, and the installed file is Latin-1 bytes with an IBM-1047 tag, so it reads as garbage. `chtag -tc ISO8859-1` on a copy makes it readable, which shows the bytes are intact. `rpm -V rsync` flags `5` on the text docs. The owner of that fix is undecided.

## Step 4: Create the spec and build

Run pax2rpm with explicit values. A pax with a non-OEF name needs `--name` and `--version`, because the defaults come from the file name.

This is the command that built the DA RPM with both scriptlets (release 7):

```
zopen-pax2rpm tagged.pax --name zps-discovery-agent --version 1.0.0 --release 7 --license IBM --summary "IBM Z Atlas Discovery Agent" --pre-script oef-license-pre.sh --post-script zps-discovery-agent-post.sh --output /u/ibmuser/data/da7/da7.spec --build-binary --buildroot /u/ibmuser/data/da7
```

- `--summary` is required. `--build-binary` builds the binary RPM only. `--build` also builds the source RPM. `--dry-run` shows the plan. `--output <file>` sets the spec file name.
- `--pre-script <file>` and `--post-script <file>` paste the contents of a shell script file into `%pre` and `%post` of the spec. These are local additions, so check `zopen-pax2rpm --help` first.
- `--requires` adds `Requires:` entries. pax2rpm sets `AutoReqProv: no`, so nothing is detected automatically.
- The pipeline calls pax2rpm from `ibm_meta/rpm.sh` as a warn-only step, so a failure never blocks the pax.
- The finished RPM is named `<name>-<version>-<release>.s390x-ibm-zos.rpm`. Read the exact name from the `Generated binary RPMs:` line, because a mistyped name only fails with `No such file`.

Do not run `setup_and_verify.sh` from a scriptlet. For the DA it pings a backend, runs `pip` installs and edits `~/.profile`.

## Step 5: Verify the RPM before installing

1. List the contents and compare with the pax file count: `rpm -qpl <rpm>`.
2. Look at the scriptlets: `rpm -qp --scripts <rpm>`.
3. Look at the requirements: `rpm -qpR <rpm>`.
4. After install, check `rpm -V <name>`, and compare file digests with the pax originals using `sha256sum`.

**Where files land.** The install prefix is `/opt/pkg`. For the DA, pax2rpm placed:

- `README.md` in `/opt/pkg/share/doc/zps-discovery-agent/`
- everything else in `/opt/pkg/share/zps-discovery-agent/misc/`, keeping `vendor/`

**Status, proven on the release 7 build:** `rpm -qpl` lists all 8 pax files in those two directories, `rpm -qp --scripts` shows both scriptlets intact, and `rpm -qpR` shows `/bin/sh` twice (once for `%pre`, once for `%post`).

## Step 6: Install and the known blockers

- Install: `rpm -Uvh <rpm>`. Verify: `rpm -V <name>`. Remove: `rpm -e <name>`.
- **Known blocker 1, proven:** a scriptlet written for `/bin/sh` makes rpm require `/bin/sh`. z/OS has `/bin/sh`, but no package owns it, so `rpm -Uvh` fails with `/bin/sh is needed by <name>`. The workaround is `rpm -Uvh --nodeps`. Do not give `--nodeps` as the long-term answer.
- **Known blocker 2, proven:** rpm's verify level is `all` (`rpm --eval '%{_pkgverify_level}'` prints `all`), so an unsigned package is refused with `does not verify: no signature`. Add `--nosignature` for local tests. Real packages will need signing.
- A Lua scriptlet (`%post -p <lua>`) might avoid the `/bin/sh` requirement. Lua works in this rpm (`rpm --eval '%{lua: print("lua works")}'` prints `lua works`). **Status: untested.** The decision is still open.
- `rsync` already installs without `--nodeps`. The pax2rpm line `%global __requires_exclude ^/usr/bin/env$` fixed its `/usr/bin/env` requirement. The same approach is **expected not to work** for `/bin/sh`. That is untested.
- **Proven:** when an upgrade fails in `%pre`, rpm leaves the old release installed. The output says `erase skipped` for the old release. When the upgrade succeeds, rpm installs the new release and then removes the old one.

## Step 7: Pre- and post-install scripts

**Post-install (proven, DA only).** `zps-discovery-agent-post.sh` is specific to the Discovery Agent. It hardcodes the DA's install path (`/opt/pkg/share/zps-discovery-agent/misc`) and its file names (`run.sh`, `setup_and_verify.sh`, `config.yaml`), so it does nothing useful for any other product. Treat it as a pattern: write a post-install script that sets the modes and tags your own product's README requires, or leave `--post-script` out. The DA script sets file modes and tags, as the DA README says. After `rpm -Uvh --nodeps --nosignature` of release 7, `run.sh` and `setup_and_verify.sh` were `-rwxr-xr-x` ISO8859-1, `config.yaml` was `-rw-------` ISO8859-1, and the binary's digest still matched the pax. `rpm -V` then showed `.M.......` on those three files, because the spec records the original modes. That is expected. Fixing it means storing the modes in the RPM.

**License prompt in `%pre` (proven on the DA RPM).** `oef-license-pre.sh` contains the license text. It:

- prints the license text,
- reads the answer from `/dev/tty`,
- exits 1 unless the answer is exactly `yes`, which makes rpm abort the install.

Results on z/OS with the DA RPM (release 7):

- Both scriptlets are in the package and survive the build intact.
- Typing `no` at the prompt blocks the install: `scriptlet failed, exit status 1`, then `install failed`. The old release stays installed (`erase skipped`).
- Typing `yes` installs the package, and rpm then removes the old release.
- Piping `echo yes` into rpm does not answer the prompt, because the script reads `/dev/tty`, not standard input.
- **Anything left in the terminal input is read as the answer.** A pasted install command declined the license because the pasted newline was read as an empty answer. When the command text was still waiting in the input after a first command, rpm read `yesrpm -Uvh ...` as the answer and also declined. Both fail safe, since only exactly `yes` is accepted, but they look like bugs. Tell testers to type the install command by hand and answer at the prompt.

Not tested: an install with no terminal at all (for example from a pipeline), discarding pending input before the `read`, and whether the prompt should be per package or one default for all OEF RPMs.

## Rules and caveats

- The guard, layout detection, `__requires_exclude` and the `--pre-script`/`--post-script` options are local changes to pax2rpm until the team decides where they go. Ask the pax2rpm owners before changing the shared copy in a way that reaches the pipeline.
- The package version `1.0.0` for the DA is a placeholder.
- The RPMs are unsigned. Signing and publishing to the repository are not done.
- The license text names "IBM Open Enterprise Foundation for z/OS (5655-OEF)". Whether that wording is right for the DA is an open question.
- A file copied from a Mac to z/OS can be corrupted by encoding conversion. After copying, repair and verify it: `iconv -f IBM-1047 -t ISO8859-1 <in> > <out> && chtag -r <out> && sha256sum <out>`. Compare with `shasum -a 256` on the Mac. Tag a repaired script `chtag -tc ISO8859-1` and `chmod +x` it, or the shell reports `FSUM7332`.
- Do not set `_BPXK_AUTOCVT` for the whole shell. It breaks the shell with `FSUM7332`.
- The LPAR sets `_TAG_REDIR_OUT=txt`. Files written by a redirect inside `rpmbuild` get tagged IBM-1047 because of it.
- The DA is a set of plain USS files, so an RPM can hold it. A product made only of MVS data sets cannot be held by an RPM.

## References

- meta repo `cicd/rpm_pipeline.jenkins`, `cicd/rpmbuild.groovy`, `cicd/publish_rpm.groovy`
- meta repo `bin/zopen-pax2rpm`

