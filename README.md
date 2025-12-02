# auto-installer

A lightweight shell script to automatically run installer scripts and install or deinstall '.deb' packages from the script directory (picks the right package for os architecture). It can download deb packages from http and/or GitHub Releases assets.

The script looks for files in the same directory, then:
- run '*preinst.sh'/'*prerm.sh' scripts
- download '.deb' assets from GitHub Releases (from 'github.conf')
- download '.deb' files from http (from 'download.conf'; optional checksum check)
- de-/install '.deb' files found in the script directory (architecture checks)
- run '*postinst.sh'/'*postrm.sh' scripts

---

## 📌 Features

- Runs installer scripts in the script directory before and after Package de-/installation
- Downloads `.deb` assets from GitHub Releases (configurable via `github.conf`; optional release tag)
- Downloads `.deb` files from any http address (configurable via `download.conf`; optional checksum check)
- Installs and removes `.deb` packages automatically (architecture checks)
- Supports `--verbose`, `--quiet`, `--force`, `--install` and `--deinstall` options
- Uses ETag/JSON caching to reduce GitHub API requests and redownloads
- Minimal external dependencies (standard shell tools + `jq`, `curl`, `dpkg`, `coreutils`)

---

## 🚀 Usage

Run the script from the repository (or script) directory:

```bash
./src/auto-installer.sh [OPTION]
```

### Options

- `-i, --install`     run scripts and install all packages
- `-d, --deinstall`   run scripts and deinstall all packages
- `-f, --force`       force deinstall or reinstall packages
- `-q, --quiet`       do not print informations while de-/installation
- `-V, --verbose`     print detailed information during de-/installation
- `-v, --version`     print script version
- `-h, --help`        show help

>  The script verifies it is running as `root` and that the system is Debian-based.

---

## ⚙️ Configuration

An optional `github.conf` file can be placed next to the script. Format:

```properties
<github_user>/<github_repository>[@<github_release_tag>] [<github_pat>]

```

Example:

```properties
aragon25/my-deb-repo
someuser/another-repo ghp_XXXXXXXXXXXXXXXXXXXX
someuser/test-repo@v1.0 ghp_XXXXXXXXXXXXXXXXXXXX
```

Each line contains `<owner>/<repo>[@<release_tag>] [<personal_access_token>]`.
Add a release tag to download a selected release instead the latest. 
Provide a token when needed (private releases or to raise rate limits).

---

An optional `download.conf` file can be placed next to the script. Format:

```properties
<link> [<filename>] [<sha512:|sha256:|sha1:|md5:|checksum>]

```

Example:

```properties
https://example.com/file.tar.gz
https://example.com/file.tar.gz file.tar.gz
https://example.com/file.tar.gz file.tar.gz sha256:abcdef1234567890
https://example.com/file.tar.gz file.tar.gz md5:abcdef1234567890
```

Each line contains `<link> [<filename>] [<sha512:|sha256:|sha1:|md5:|checksum>]`.
Select optional filename to rename the downloaded file. 
Provide a checksum if you want to verify downloaded file.

---

## 📝 Behavior

- `--install`:
  - Executes all `*preinst.sh` scripts found in the same directory.
  - Calls `github_download` to fetch `.deb` assets from repositories listed in `github.conf`.
  - Calls `download_files` to fetch `.deb` files from http listed in `download.conf`.
  - Installs `.deb` files using `apt-get` after checking package architecture; incompatible packages are skipped.
  - Executes all `*postinst.sh` scripts found in the same directory.
- `--deinstall`:
  - Executes all `*prerm.sh` scripts found in the same directory.
  - Calls `github_download` to fetch `.deb` assets from repositories listed in `github.conf`.
  - Calls `download_files` to fetch `.deb` files from http listed in `download.conf`.
  - Removes installed `.deb` packages via `apt-get remove`.
  - Executes all `*postrm.sh` scripts found in the same directory.

The script stores ETag/cache data in a local `.etag` directory to avoid unnecessary GitHub API calls and redownloads.

---

## 🧰 Dependencies

The script expects the following programs on Debian-based systems:

- `bash`
- `dpkg`, `dpkg-deb`
- `apt-get`
- `curl`
- `jq`
- `file`, `find`, `sed`, `grep`, `stat`
- `md5sum`, `sha512sum`, `sha256sum`, `sha1sum`

If required tools are missing the script will get it trough apt-get.

---

## 📜 Examples

Install (from repository root):

```bash
sudo ./src/auto-installer.sh --install
```

Silent install (for automation):

```bash
sudo ./src/auto-installer.sh --install --quiet
```

Deinstall:

```bash
sudo ./src/auto-installer.sh --deinstall
```

---

## 🧪 Troubleshooting

- "This script can only run with Superuser privileges!": run the script with `sudo`.
- "This script is only supported on Debian-based systems.": the script is designed for Debian/Ubuntu/Raspbian.
- GitHub download issues: verify `github.conf`, tags, tokens, and API rate limits.
