import { test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { tmpdir } from "node:os";
import { spawn, spawnSync } from "node:child_process";

const [configured, plain, renamed] = process.argv.slice(2);
const root = fs.mkdtempSync(join(tmpdir(), "pi-config-tests-"));
const env = { ...process.env, HOME: join(root, "home with spaces") };
delete env.PI_CODING_AGENT_DIR;
delete env.PI_CODING_AGENT_SESSION_DIR;
delete env.XDG_STATE_HOME;
function run(script, directory, args = ["list"], extra = {}) {
  const result = spawnSync(script, args, {
    env: { ...env, ...(directory === undefined ? {} : { PI_CODING_AGENT_DIR: directory }), ...extra },
    encoding: "utf8",
  });
  assert.equal(result.error, undefined);
  return result;
}
function success(result) {
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /^pi-started:/);
}
const contents = (directory, name) => fs.readFileSync(join(directory, name), "utf8");
function noStaging(directory) {
  assert.ok(!fs.readdirSync(directory, { recursive: true }).some(name => name.includes(".pi-extra-config-")));
}

test("text/JSON compose; sources, spaces, permissions, and subcommand dispatch work", () => {
  const directory = join(root, "caller config");
  const result = run(configured, directory);
  success(result);
  assert.equal(result.stdout, "pi-started:list\n");
  assert.equal(contents(directory, "AGENTS.md"), "Shared instructions.\nWork instructions.");
  assert.deepEqual(JSON.parse(contents(directory, "extension.json")), {
    enabled: true, nested: { shared: 1, work: 2 }, items: ["first", "second"],
  });
  assert.equal(contents(directory, "nested dir/source.txt"), "copied verbatim\n");
  assert.equal(contents(directory, "literal ' $ file"), "not shell-expanded");
  assert.equal(contents(directory, "empty.txt"), "");
  assert.equal(contents(directory, "local.txt"), "Local source fixture.\n");
  assert.equal(contents(directory, "local-string.txt"), "Local source fixture.\n");
  for (const name of ["AGENTS.md", "extension.json", "nested dir/source.txt"]) {
    assert.equal(fs.statSync(join(directory, name)).mode & 0o777, 0o600);
    assert.equal(fs.lstatSync(join(directory, name)).isSymbolicLink(), false);
  }
  noStaging(directory);
});

test("seed preserves edits and malformed JSON; enforce replaces; unrelated state survives", () => {
  const directory = join(root, "ownership");
  success(run(configured, directory));
  fs.writeFileSync(join(directory, "extension.json"), "not valid JSON");
  fs.writeFileSync(join(directory, "AGENTS.md"), "manual edit");
  fs.writeFileSync(join(directory, "nested dir/enforced.json"), "not JSON either");
  fs.writeFileSync(join(directory, "auth.json"), "private state");
  fs.chmodSync(join(directory, "extension.json"), 0o640);
  success(run(configured, directory, ["--help"]));
  assert.equal(contents(directory, "extension.json"), "not valid JSON");
  assert.equal(fs.statSync(join(directory, "extension.json")).mode & 0o777, 0o640);
  assert.equal(contents(directory, "AGENTS.md"), "Shared instructions.\nWork instructions.");
  assert.deepEqual(JSON.parse(contents(directory, "nested dir/enforced.json")), { value: 42 });
  assert.equal(contents(directory, "auth.json"), "private state");
  // Removing declarations is not an instruction to delete their files.
  success(run(plain, directory));
  assert.equal(contents(directory, "extension.json"), "not valid JSON");
  noStaging(directory);
});

test("effective directory follows caller, configDir, default, XDG, and tilde semantics", () => {
  success(run(configured));
  assert.ok(fs.existsSync(join(env.HOME, "config with spaces/AGENTS.md")));
  success(run(plain));
  assert.equal(contents(join(env.HOME, ".pi/agent"), "default.txt"), "default");
  success(run(plain, ""));
  success(run(plain, "~/tilde config"));
  assert.equal(contents(join(env.HOME, "tilde config"), "default.txt"), "default");
  const urlDirectory = join(root, "file URL");
  success(run(plain, pathToFileURL(urlDirectory).href));
  assert.equal(contents(urlDirectory, "default.txt"), "default");
  success(run(renamed));
  assert.equal(contents(join(env.HOME, ".local/state/pi/pi-renamed"), "default.txt"), "default");
  const xdg = join(root, "XDG state");
  success(run(renamed, undefined, ["list"], { XDG_STATE_HOME: xdg }));
  assert.equal(contents(join(xdg, "pi/pi-renamed"), "default.txt"), "default");
});

test("seed never follows or replaces an existing destination, including dangling symlinks", () => {
  const directory = join(root, "seed links");
  fs.mkdirSync(directory);
  const target = join(root, "absent target");
  fs.symlinkSync(target, join(directory, "extension.json"));
  fs.mkdirSync(join(directory, "empty.txt"));
  success(run(configured, directory));
  assert.equal(fs.readlinkSync(join(directory, "extension.json")), target);
  assert.equal(fs.existsSync(target), false);
  assert.ok(fs.statSync(join(directory, "empty.txt")).isDirectory());
});

test("enforce rejects symlinks and directories without starting Pi or touching their targets", () => {
  for (const kind of ["symlink", "directory"]) {
    const directory = join(root, `enforce ${kind}`);
    fs.mkdirSync(directory);
    const target = join(root, "protected file");
    fs.writeFileSync(target, "untouched");
    if (kind === "symlink") fs.symlinkSync(target, join(directory, "AGENTS.md"));
    else fs.mkdirSync(join(directory, "AGENTS.md"));
    const result = run(configured, directory);
    assert.equal(result.status, 1);
    assert.equal(result.stdout, "");
    assert.match(result.stderr, /AGENTS.md: refusing to replace/);
    assert.equal(fs.readFileSync(target, "utf8"), "untouched");
    noStaging(directory);
  }
});

test("nested symlink parents are rejected; explicitly symlinked agent roots are supported", () => {
  const directory = join(root, "nested symlink");
  const outside = join(root, "outside");
  fs.mkdirSync(directory);
  fs.mkdirSync(outside);
  fs.symlinkSync(outside, join(directory, "nested dir"));
  const result = run(configured, directory);
  assert.equal(result.status, 1);
  assert.equal(result.stdout, "");
  assert.match(result.stderr, /parent is not a real directory/);
  assert.deepEqual(fs.readdirSync(outside), []);
  const alias = join(root, "root alias");
  fs.symlinkSync(outside, alias);
  success(run(configured, alias));
  assert.ok(fs.existsSync(join(outside, "AGENTS.md")));
});

test("write failures abort startup without leaking staging files", () => {
  const directory = join(root, "read only");
  fs.mkdirSync(directory, { mode: 0o500 });
  try {
    const result = run(configured, directory);
    assert.equal(result.status, 1);
    assert.equal(result.stdout, "");
    assert.match(result.stderr, /EACCES/);
    noStaging(directory);
  } finally {
    fs.chmodSync(directory, 0o700);
  }
});

test("concurrent launches publish complete files without clobbering seed edits", async () => {
  const directory = join(root, "concurrent");
  const launch = () => new Promise((resolve, reject) => {
    const child = spawn(configured, ["list"], { env: { ...env, PI_CODING_AGENT_DIR: directory } });
    let stderr = "";
    child.stderr.on("data", chunk => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", code => code === 0 ? resolve() : reject(new Error(stderr)));
  });
  await Promise.all(Array.from({ length: 12 }, launch));
  assert.equal(contents(directory, "AGENTS.md"), "Shared instructions.\nWork instructions.");
  assert.deepEqual(JSON.parse(contents(directory, "nested dir/enforced.json")), { value: 42 });
  fs.writeFileSync(join(directory, "extension.json"), "user owns this");
  await Promise.all(Array.from({ length: 12 }, launch));
  assert.equal(contents(directory, "extension.json"), "user owns this");
  noStaging(directory);
});
