// Install writable config files without truncating an existing destination.
// The agent directory is trusted user-owned state, not a security boundary
// against another process concurrently changing its directory structure.
import * as fs from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

function stat(path) {
  try {
    return fs.lstatSync(path);
  } catch (error) {
    if (error.code === "ENOENT") return undefined;
    throw error;
  }
}

function install(root, { name, source, mode }) {
  const parts = name.split("/");
  let parent = root;
  for (const part of parts.slice(0, -1)) {
    parent = join(parent, part);
    try {
      fs.mkdirSync(parent, { mode: 0o700 });
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
    }
    // Do not follow an existing symlink outside the selected agent directory.
    if (!fs.lstatSync(parent).isDirectory()) {
      throw new Error(`parent is not a real directory: ${parent}`);
    }
  }

  const destination = join(parent, parts.at(-1));
  const existing = stat(destination);
  if (mode === "seed" && existing) return;
  if (existing && !existing.isFile()) {
    throw new Error(`refusing to replace a symlink or non-regular file: ${destination}`);
  }
  if (!fs.statSync(source).isFile()) {
    throw new Error(`source is not a regular file: ${source}`);
  }

  // A private, same-filesystem staging directory allows atomic publication and
  // keeps temporary contents private even under a permissive caller umask.
  const staging = fs.mkdtempSync(join(dirname(destination), ".pi-extra-config-"));
  const temporary = join(staging, "contents");
  try {
    fs.writeFileSync(temporary, fs.readFileSync(source), { mode: 0o600, flag: "wx" });
    fs.chmodSync(temporary, 0o600);
    if (mode === "seed") {
      try {
        // Unlike rename, link cannot overwrite a file created by another writer.
        fs.linkSync(temporary, destination);
      } catch (error) {
        if (error.code !== "EEXIST") throw error;
      }
    } else {
      fs.renameSync(temporary, destination);
    }
  } finally {
    fs.rmSync(staging, { recursive: true, force: true });
  }
}

try {
  const configured = process.env.PI_CODING_AGENT_DIR;
  // Match Pi's default, empty-variable fallback, ~/ expansion, and file URLs.
  const directory = !configured ? join(homedir(), ".pi", "agent")
    : configured === "~" ? homedir()
    : configured.startsWith("~/") ? join(homedir(), configured.slice(2))
    : configured.startsWith("file://") ? fileURLToPath(configured)
    : configured;
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  // Allow a symlink for the explicitly selected root, but not within it.
  const root = fs.realpathSync(resolve(directory));
  const files = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
  for (const file of files) {
    try {
      install(root, file);
    } catch (error) {
      throw new Error(`${file.name}: ${error.message}`);
    }
  }
} catch (error) {
  console.error(`pi wrapper: extraConfigFiles: ${error.message}`);
  process.exitCode = 1;
}
