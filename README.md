# auto-installer

A lightweight shell script to automatically run installer scripts and download/install `.deb` packages from GitHub Releases. The script looks for files in the same directory, executes `*-installer.sh` scripts (except itself) and installs any `.deb` files found.

---

## 📦 Features

- Runs all `*-installer.sh` installer scripts in the script directory
- Downloads `.deb` assets from GitHub Releases (configurable via `github.conf`)
- Installs and removes `.deb` packages automatically (architecture checks)
- Supports `--quiet`, `--force`, `--install` and `--deinstall` options
- Uses ETag/JSON caching to reduce GitHub API requests
- Minimal external dependencies (standard shell tools + `jq`, `curl`, `dpkg`)

---

## 🧪 Usage

Run the script from the repository (or script) directory:

```bash
./src/auto-installer.sh [OPTION]
```

### Options

- `-i, --install`     run all `*-installer.sh` scripts and install `.deb` packages
- `-d, --deinstall`   deinstall packages (installer scripts are invoked with `-d`)
- `-f, --force`       force reinstall/remove (passed to apt calls)
- `-q, --quiet`       reduce output (suitable for automation)
- `-v, --version`     print script version
- `-h, --help`        show help

>  The script verifies it is running as `root` and that the system is Debian-based.

---

## ⚙️ Configuration

An optional `github.conf` file can be placed next to the script. Format:

```properties
#{owner/repo} {personal_access_token,optional}
#{owner/repo2} {personal_access_token,optional}

```

Example:

```properties
aragon25/my-deb-repo
someuser/another-repo ghp_XXXXXXXXXXXXXXXXXXXX
```

Each line contains `<owner>/<repo> [<personal_access_token>]`. Provide a token when needed (private releases or to raise rate limits).

---

## 📝 Behavior

- `--install`:
  - Calls `github_download` to fetch `.deb` assets from repositories listed in `github.conf`.
  - Executes all `*-installer.sh` scripts (except the main script) found in the same directory.
  - Installs `.deb` files using `apt-get` after checking package architecture; incompatible packages are skipped.
- `--deinstall`:
  - Invokes installer scripts with `-d` and removes installed `.deb` packages via `apt-get remove`.

The script stores ETag/cache data in a local `.etag` directory to avoid unnecessary GitHub API calls.

---

## 🧰 Dependencies

The script expects the following programs on Debian-based systems:

- `bash`
- `dpkg`, `dpkg-deb`
- `apt-get`
- `curl`
- `jq`
- `file`, `find`, `sed`, `grep`, `stat`

If required tools are missing the script will abort with an error message.

---

## ⚙️ Examples

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
- GitHub download issues: verify `github.conf`, tokens, and API rate limits.
