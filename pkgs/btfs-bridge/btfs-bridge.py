#!/usr/bin/env python3
"""
BTFS Bridge: Watches qBittorrent for torrents in the "stream" category
and mounts them via BTFS for on-demand streaming instead of full download.
"""

import argparse
import json
import logging
import os
import signal
import subprocess
import sys
import time
import urllib.parse
import urllib.request

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("btfs-bridge")


class QBittorrentAPI:
    def __init__(self, host: str, port: int, username: str, password: str):
        self.base_url = f"http://{host}:{port}/api/v2"
        self.username = username
        self.password = password
        self.cookie = None

    def _request(self, path: str, data: dict | None = None) -> bytes:
        url = f"{self.base_url}{path}"
        if data is not None:
            encoded = urllib.parse.urlencode(data).encode()
            req = urllib.request.Request(url, data=encoded)
        else:
            req = urllib.request.Request(url)

        if self.cookie:
            req.add_header("Cookie", self.cookie)

        resp = urllib.request.urlopen(req, timeout=30)

        # Capture session cookie
        cookie_header = resp.headers.get("Set-Cookie")
        if cookie_header:
            self.cookie = cookie_header.split(";")[0]

        return resp.read()

    def login(self) -> bool:
        try:
            result = self._request(
                "/auth/login",
                {"username": self.username, "password": self.password},
            )
            return result.decode().strip() == "Ok."
        except Exception as e:
            log.error("Failed to login to qBittorrent: %s", e)
            return False

    def get_torrents(self, category: str) -> list[dict]:
        try:
            data = self._request(
                "/torrents/info",
                {"category": category},
            )
            return json.loads(data)
        except Exception as e:
            log.error("Failed to get torrents: %s", e)
            return []

    def get_torrent_properties(self, torrent_hash: str) -> dict | None:
        try:
            data = self._request(
                "/torrents/properties",
                {"hash": torrent_hash},
            )
            return json.loads(data)
        except Exception as e:
            log.error("Failed to get torrent properties for %s: %s", torrent_hash, e)
            return None

    def pause_torrent(self, torrent_hash: str) -> bool:
        try:
            self._request("/torrents/pause", {"hashes": torrent_hash})
            return True
        except Exception as e:
            log.error("Failed to pause torrent %s: %s", torrent_hash, e)
            return False

    def add_torrent_tags(self, torrent_hash: str, tags: str) -> bool:
        try:
            self._request("/torrents/addTags", {"hashes": torrent_hash, "tags": tags})
            return True
        except Exception as e:
            log.error("Failed to tag torrent %s: %s", torrent_hash, e)
            return False

    def set_torrent_category(self, torrent_hash: str, category: str) -> bool:
        try:
            self._request(
                "/torrents/setCategory",
                {"hashes": torrent_hash, "category": category},
            )
            return True
        except Exception as e:
            log.error("Failed to set category for %s: %s", torrent_hash, e)
            return False


def extract_magnet(torrent: dict) -> str | None:
    """Extract or reconstruct the magnet link from torrent info."""
    magnet_uri = torrent.get("magnet_uri")
    if magnet_uri:
        return magnet_uri

    # Reconstruct from hash
    torrent_hash = torrent.get("hash", "")
    name = torrent.get("name", "")
    if torrent_hash:
        magnet = f"magnet:?xt=urn:btih:{torrent_hash}"
        if name:
            magnet += f"&dn={urllib.parse.quote(name)}"
        return magnet

    return None


def derive_mount_name(torrent: dict) -> str:
    """Derive a mount directory name from torrent metadata, organized by category source."""
    name = torrent.get("name", torrent.get("hash", "unknown"))
    # Clean the name for filesystem use
    clean = "".join(c if c.isalnum() or c in " .-_()" else "_" for c in name).strip()
    return clean


def get_source_from_tags(torrent: dict) -> str:
    """Determine whether this came from radarr or sonarr based on tags/save path."""
    tags = torrent.get("tags", "").lower()
    save_path = torrent.get("save_path", "").lower()
    category = torrent.get("category", "").lower()

    if "radarr" in tags or "movie" in save_path or "radarr" in category:
        return "radarr"
    elif "sonarr" in tags or "tv" in save_path or "sonarr" in category:
        return "sonarr"
    return "unknown"


def process_stream_torrent(
    qbt: QBittorrentAPI, torrent: dict, processed_hashes: set
) -> bool:
    """Process a single torrent: extract magnet, trigger BTFS mount, pause download."""
    torrent_hash = torrent["hash"].lower()

    if torrent_hash in processed_hashes:
        return False

    magnet = extract_magnet(torrent)
    if not magnet:
        log.warning("Could not extract magnet for torrent %s", torrent_hash)
        processed_hashes.add(torrent_hash)
        return False

    source = get_source_from_tags(torrent)
    mount_name = derive_mount_name(torrent)

    # Organize by source: Movies/ or TV/
    if source == "radarr":
        mount_name = f"Movies/{mount_name}"
    elif source == "sonarr":
        mount_name = f"TV/{mount_name}"

    log.info(
        "Processing torrent: %s (hash: %s, source: %s)",
        torrent.get("name", "unknown"),
        torrent_hash,
        source,
    )

    # Add to BTFS via btfs-manager
    try:
        result = subprocess.run(
            ["btfs-manager", "add", magnet, mount_name, source],
            capture_output=True,
            text=True,
            timeout=60,
        )
        if result.returncode != 0:
            log.error("btfs-manager add failed: %s", result.stderr)
            return False
        log.info("BTFS mount created: %s", mount_name)
    except subprocess.TimeoutExpired:
        log.error("btfs-manager add timed out for %s", torrent_hash)
        return False
    except FileNotFoundError:
        log.error("btfs-manager not found in PATH")
        return False

    # Pause the qBittorrent download (keep metadata for arr stack)
    qbt.pause_torrent(torrent_hash)

    # Tag as btfs-mounted so we can identify it
    qbt.add_torrent_tags(torrent_hash, "btfs-mounted")

    processed_hashes.add(torrent_hash)
    log.info("Successfully bridged torrent %s to BTFS", torrent_hash)
    return True


def load_processed_hashes(state_file: str) -> set:
    """Load previously processed hashes from state file."""
    if os.path.exists(state_file):
        try:
            with open(state_file) as f:
                return set(json.load(f))
        except (json.JSONDecodeError, IOError):
            pass
    return set()


def save_processed_hashes(state_file: str, hashes: set):
    """Save processed hashes to state file."""
    os.makedirs(os.path.dirname(state_file), exist_ok=True)
    with open(state_file, "w") as f:
        json.dump(list(hashes), f)


def main():
    parser = argparse.ArgumentParser(description="BTFS Bridge for qBittorrent")
    parser.add_argument(
        "--qbt-host", default="127.0.0.1", help="qBittorrent WebUI host"
    )
    parser.add_argument(
        "--qbt-port", type=int, default=8080, help="qBittorrent WebUI port"
    )
    parser.add_argument("--qbt-username", default="admin", help="qBittorrent username")
    parser.add_argument(
        "--qbt-password-file", help="File containing qBittorrent password"
    )
    parser.add_argument(
        "--category",
        default="stream",
        help="qBittorrent category to watch for streaming torrents",
    )
    parser.add_argument(
        "--poll-interval",
        type=int,
        default=15,
        help="Seconds between polling qBittorrent",
    )
    parser.add_argument(
        "--state-file",
        default="/var/lib/btfs-bridge/processed.json",
        help="File to track processed torrent hashes",
    )
    args = parser.parse_args()

    # Read password
    password = "adminadmin"  # qBittorrent default
    if args.qbt_password_file:
        try:
            with open(args.qbt_password_file) as f:
                password = f.read().strip()
        except IOError as e:
            log.error("Failed to read password file: %s", e)
            sys.exit(1)

    qbt = QBittorrentAPI(args.qbt_host, args.qbt_port, args.qbt_username, password)

    # Graceful shutdown
    running = True

    def handle_signal(signum, frame):
        nonlocal running
        log.info("Received signal %d, shutting down...", signum)
        running = False

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    processed_hashes = load_processed_hashes(args.state_file)
    log.info(
        "Starting BTFS Bridge (watching category: %s, %d previously processed)",
        args.category,
        len(processed_hashes),
    )

    login_backoff = 5
    while running:
        if not qbt.cookie:
            if not qbt.login():
                log.warning(
                    "Login failed, retrying in %d seconds...", login_backoff
                )
                time.sleep(login_backoff)
                login_backoff = min(login_backoff * 2, 120)
                continue
            login_backoff = 5
            log.info("Logged in to qBittorrent")

        torrents = qbt.get_torrents(args.category)

        for torrent in torrents:
            # Skip torrents already tagged as btfs-mounted
            tags = torrent.get("tags", "")
            if "btfs-mounted" in tags:
                processed_hashes.add(torrent["hash"].lower())
                continue

            if process_stream_torrent(qbt, torrent, processed_hashes):
                save_processed_hashes(args.state_file, processed_hashes)

        time.sleep(args.poll_interval)

    log.info("BTFS Bridge stopped")


if __name__ == "__main__":
    main()
